#!/bin/bbash

set -e

MAGMA_VERSION="c62d70"

function do_install() {
    rocm_version=$1
    rocm_version_nodot=${1/./}
    
    if [[ ${rocm_version_nodot} == 54 ]]; then
        magma_archive="magma-rocm${rocm_version}-${MAGMA_VERSION}-0.tar.bz2"
    elif [[ ${rocm_version_nodot} == 53 ]]; then
	magma_archive="magma-cuda${rocm_version}-${MAGMA_VERSION}-0.tar.bz2"
    fi
    
    rocm_dir="/opt/rocm"
    (
        set -x
        tmp_dir=$(mktemp -d)
        pushd ${tmp_dir}
        wget -q https://anaconda.org/pytorch/magma-rocm${rocm_version}/${MAGMA_VERSION}/download/linux-64/${magma_archive}
        tar -xvf "${magma_archive}"
        mkdir -p "${rocm_dir}/magma"
        mv include "${rocm_dir}/magma/include"
        mv lib "${rocm_dir}/magma/lib"
        popd
    )
}

do_install $1
