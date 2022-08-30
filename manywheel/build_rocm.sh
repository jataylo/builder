#!/usr/bin/env bash

set -ex

export ROCM_HOME=/opt/rocm
export MAGMA_HOME=$ROCM_HOME/magma
# TODO: libtorch_cpu.so is broken when building with Debug info
export BUILD_DEBUG_INFO=0

# TODO Are these all used/needed?
export TH_BINARY_BUILD=1
export USE_STATIC_CUDNN=1
export USE_STATIC_NCCL=1
export ATEN_STATIC_CUDA=1
export USE_CUDA_STATIC_LINK=1
export INSTALL_TEST=0 # dont install test binaries into site-packages

# ROCBLAS paths
ROCBLAS_LIB_SRC=$ROCM_HOME/lib/rocblas/library
ROCBLAS_LIB_DST=lib/rocblas/library

# Keep an array of cmake variables to add to
if [[ -z "$CMAKE_ARGS" ]]; then
    # These are passed to tools/build_pytorch_libs.sh::build()
    CMAKE_ARGS=()
fi
if [[ -z "$EXTRA_CAFFE2_CMAKE_FLAGS" ]]; then
    # These are passed to tools/build_pytorch_libs.sh::build_caffe2()
    EXTRA_CAFFE2_CMAKE_FLAGS=()
fi

# Determine ROCm version and architectures to build for
#
# NOTE: We should first check `DESIRED_CUDA` when determining `ROCM_VERSION`
if [[ -n "$DESIRED_CUDA" ]]; then
    if ! echo "${DESIRED_CUDA}"| grep "^rocm" >/dev/null 2>/dev/null; then
        export DESIRED_CUDA="rocm${DESIRED_CUDA}"
    fi
    # rocm3.7, rocm3.5.1
    ROCM_VERSION="$DESIRED_CUDA"
    echo "Using $ROCM_VERSION as determined by DESIRED_CUDA"
else
    echo "Must set DESIRED_CUDA"
    exit 1
fi

# Package directories
WHEELHOUSE_DIR="wheelhouse$ROCM_VERSION"
LIBTORCH_HOUSE_DIR="libtorch_house$ROCM_VERSION"
if [[ -z "$PYTORCH_FINAL_PACKAGE_DIR" ]]; then
    if [[ -z "$BUILD_PYTHONLESS" ]]; then
        PYTORCH_FINAL_PACKAGE_DIR="/remote/wheelhouse$ROCM_VERSION"
    else
        PYTORCH_FINAL_PACKAGE_DIR="/remote/libtorch_house$ROCM_VERSION"
    fi
fi
mkdir -p "$PYTORCH_FINAL_PACKAGE_DIR" || true

# Required ROCm libraries
ROCM_SO_FILES=(
    "libMIOpen.so"
    "libamdhip64.so"
    "libhipblas.so"
    "libhipfft.so"
    "libhiprand.so"
    "libhipsparse.so"
    "libhsa-runtime64.so"
    "libamd_comgr.so"
    "libmagma.so"
    "librccl.so"
    "librocblas.so"
    "librocfft-device-0.so"
    "librocfft-device-1.so"
    "librocfft-device-2.so"
    "librocfft-device-3.so"
    "librocfft.so"
    "librocm_smi64.so"
    "librocrand.so"
    "librocsolver.so"
    "librocsparse.so"
    "libroctracer64.so"
    "libroctx64.so"
)

OS_NAME=`awk -F= '/^NAME/{print $2}' /etc/os-release`
if [[ "$OS_NAME" == *"CentOS Linux"* ]]; then
    LIBGOMP_PATH="/usr/lib64/libgomp.so.1"
    LIBNUMA_PATH="/usr/lib64/libnuma.so.1"
    LIBELF_PATH="/usr/lib64/libelf.so.1"
    LIBTINFO_PATH="/usr/lib64/libtinfo.so.5"
    LIBDRM_PATH="/opt/amdgpu/lib64/libdrm.so.2"
    LIBDRM_AMDGPU_PATH="/opt/amdgpu/lib64/libdrm_amdgpu.so.1"
    MAYBE_LIB64=lib64
elif [[ "$OS_NAME" == *"Ubuntu"* ]]; then
    LIBGOMP_PATH="/usr/lib/x86_64-linux-gnu/libgomp.so.1"
    LIBNUMA_PATH="/usr/lib/x86_64-linux-gnu/libnuma.so.1"
    LIBELF_PATH="/usr/lib/x86_64-linux-gnu/libelf.so.1"
    LIBTINFO_PATH="/lib/x86_64-linux-gnu/libtinfo.so.5"
    LIBDRM_PATH="/usr/lib/x86_64-linux-gnu/libdrm.so.2"
    LIBDRM_AMDGPU_PATH="/usr/lib/x86_64-linux-gnu/libdrm_amdgpu.so.1"
    MAYBE_LIB64=lib
fi
OS_SO_PATHS=($LIBGOMP_PATH $LIBNUMA_PATH\ 
             $LIBELF_PATH $LIBTINFO_PATH\
             $LIBDRM_PATH $LIBDRM_AMDGPU_PATH)
OS_SO_FILES=()
for lib in "${OS_SO_PATHS[@]}"
do
    file_name="${lib##*/}"
    OS_SO_FILES[${#OS_SO_FILES[@]}]=$file_name
done

# To make version comparison easier, create an integer representation.
ROCM_VERSION_CLEAN=$(echo ${ROCM_VERSION} | sed s/rocm//)
save_IFS="$IFS"
IFS=. ROCM_VERSION_ARRAY=(${ROCM_VERSION_CLEAN})
IFS="$save_IFS"
if [[ ${#ROCM_VERSION_ARRAY[@]} == 2 ]]; then
    ROCM_VERSION_MAJOR=${ROCM_VERSION_ARRAY[0]}
    ROCM_VERSION_MINOR=${ROCM_VERSION_ARRAY[1]}
    ROCM_VERSION_PATCH=0
elif [[ ${#ROCM_VERSION_ARRAY[@]} == 3 ]]; then
    ROCM_VERSION_MAJOR=${ROCM_VERSION_ARRAY[0]}
    ROCM_VERSION_MINOR=${ROCM_VERSION_ARRAY[1]}
    ROCM_VERSION_PATCH=${ROCM_VERSION_ARRAY[2]}
else
    echo "Unhandled ROCM_VERSION ${ROCM_VERSION}"
    exit 1
fi
ROCM_INT=$(($ROCM_VERSION_MAJOR * 10000 + $ROCM_VERSION_MINOR * 100 + $ROCM_VERSION_PATCH))

# ROCBLAS library files
ARCH=$(echo $PYTORCH_ROCM_ARCH | sed 's/;/|/g')
KERNEL_FILES=$(ls -l $ROCBLAS_LIB_SRC | \
               grep -Eo Kernels.\* | \
               grep -E $ARCH)
TENSILE_FILES=$(ls -l $ROCBLAS_LIB_SRC | \
               grep -Eo Tensile.\* | \
               grep -E $ARCH)
if [[ $ROCM_INT -lt 50200 ]]; then
    TENSILE_FILES+=" TensileLibrary.dat"
fi
ROCBLAS_LIB_FILES=($KERNEL_FILES $TENSILE_FILES)

# ROCm lib files
ROCM_SO_PATHS=()
for lib in "${ROCM_SO_FILES[@]}"
do
    file_path=($(find $ROCM_HOME/lib/ -name "$lib"))
    if [[ -z $file_path ]]; then 
        file_path=($(find $ROCM_HOME/lib64/ -name "$lib"))
    fi
    if [[ -z $file_path ]]; then 
        file_path=($(find $ROCM_HOME/ -name "$lib"))
    fi
    ROCM_SO_PATHS[${#ROCM_SO_PATHS[@]}]="$file_path"
done

DEPS_LIST=(
    ${ROCM_SO_PATHS[*]}
    ${OS_SO_PATHS[*]}
)

DEPS_SONAME=(
    ${ROCM_SO_FILES[*]}
    ${OS_SO_FILES[*]}
)

DEPS_AUX_SRCLIST=(
    "${ROCBLAS_LIB_FILES[@]/#/$ROCBLAS_LIB_SRC/}"
    "/opt/amdgpu/share/libdrm/amdgpu.ids"
)

DEPS_AUX_DSTLIST=(
    "${ROCBLAS_LIB_FILES[@]/#/$ROCBLAS_LIB_DST/}"
    "share/libdrm/amdgpu.ids"
)

echo "PYTORCH_ROCM_ARCH: ${PYTORCH_ROCM_ARCH}"

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
if [[ -z "$BUILD_PYTHONLESS" ]]; then
    BUILD_SCRIPT=build_common.sh
else
    BUILD_SCRIPT=build_libtorch.sh
fi
source $SCRIPTPATH/${BUILD_SCRIPT}
