#!/bin/bash

set -e

bash ./install_conda.sh
export PATH=/opt/conda/bin:$PATH

PACKAGE_DIR=${PACKAGE_NAME}
PACKAGE_FILES=package_files
mkdir ${PACKAGE_DIR}
cp ${PACKAGE_FILES}/build.sh ${PACKAGE_DIR}/build.sh
cp ${PACKAGE_FILES}/meta.yaml ${PACKAGE_DIR}/meta.yaml

conda install -yq conda-build conda-verify
(
    set -x
    conda build --output-folder output "${PACKAGE_DIR}"
)
