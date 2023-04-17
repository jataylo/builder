#!/usr/bin/env bash

#!/bin/bash

set -ex

function do_install() {

    MAGMA_VERSION="2.6.2"

    # Temporary hard coded addresses
    if [[ $ROCM_VERSION == 5.5 ]]; then
        magma_archive="https://compute-artifactory.amd.com/artifactory/rocm-pytorch-conda/rocm-pkgs/35/linux-64/magma-rocm-2.6.2-+RC5_44_35.tar.bz2"
    elif [[ $ROCM_VERSION == 5.4 ]]; then
        magma_archive="https://compute-artifactory.amd.com/artifactory/rocm-pytorch-conda/rocm-pkgs/11/linux-64/magma-rocm-2.6.2-+rel_11.tar.bz2"
    elif [[ $ROCM_VERSION == 5.3 ]]; then
        magma_archive="https://compute-artifactory.amd.com/artifactory/rocm-pytorch-conda/rocm-pkgs/7/linux-64/magma-rocm-2.6.2-+dev_7.tar.bz2"
    else
        echo "Unhandled ROCM_VERSION ${ROCM_VERSION}"
        exit 1
    fi

    rocm_path="/opt/rocm/"
    tmp_dir=$(mktemp -d)
    pushd ${tmp_dir}
    wget --no-check-certificate -q $magma_archive
    mkdir -p "${rocm_path}/magma"
    mv $tmp_dir/magma/include "${rocm_path}/magma/include"
    mv $tmp_dir/magma/lib "${rocm_path}/magma/lib"
    echo "$tmp_dir/magma/include"
    echo "$rocm_path/magma/include"
    echo "$tmp_dir/magma/lib"
    echo "$rocm_path/magma/lib"
    popd
}
