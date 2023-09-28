#! /bin/bash -e

if [[ -z "${DPCPP_REPO_DIR}" ]]
then
    echo "Error: set DPCPP_REPO_DIR pointing at a DPC++ repository"
    exit 1
fi

if [[ -z "${SLURM_DESTINATION}" ]]
then
    echo "Error: set SLURM_DESTINATION to destination to be used in the slurm machine"
    exit 1
fi

if [[ -z "${SYCL_BENCH_CI_RESULTS_DIR}" ]]
then
    echo "Error: set SYCL_BENCH_CI_RESULTS_DIR pointing at sycl-bench performance regression testing directory"
    exit 1
fi

SYCL_BENCH_DIR=$(dirname $(realpath $0))/..
WORKDIR=/tmp/sycl-bench-ci-workdir

mkdir -p $WORKDIR

pushd $WORKDIR

echo "Cleaning working directory"
rm -rf ./*

# Get latest artifacts
pushd $DPCPP_REPO_DIR
WORKFLOW_ID=$(gh run list -w "Reusable SYCL Linux build workflow" \
                 --json workflowDatabaseId -L1 --jq ".[].workflowDatabaseId")
# Run "Reusable SYCL Linux build workflow" providing all options. These options
# are not configurable.
gh workflow run $WORKFLOW_ID -r sycl-mlir -f changes="[]" \
   -f build_image="ghcr.io/intel/llvm/sycl_ubuntu2204_nightly:build" \
   -f cc=gcc -f cxx=g++ -f build_configure_extra_args="--hip --cuda" \
   -f build_cache_root="/__w/" -f build_cache_suffix="default" \
   -f build_artifact_suffix="default" -f retention-days="3"
# Sleep 10 s to let workflow start
sleep 10
RUN_ID=$(gh run list -L1 --json databaseId --jq ".[].databaseId" -w "Reusable SYCL Linux build workflow")
# Wait for workflow and check status every 60 s
gh run watch $RUN_ID --exit-status -i 60
echo "Downloading artifacts (https://github.com/intel/llvm/actions/runs/$RUN_ID) to $WORKDIR"
gh run download $RUN_ID -D $WORKDIR
popd # $DPCPP_REPO_DIR

echo "Unpack and repacks artifacts using gzip"
repack_artifact() {
    echo "Repacking artifact $1"
    TMP_ARCHIVE=llvm_sycl.tar
    pushd $1
    # Uncompress using zstd
    unzstd llvm_sycl.tar.zst -o $TMP_ARCHIVE
    # Untar
    tar -xf $TMP_ARCHIVE
    # Compress archive to copy to slurm
    gzip $TMP_ARCHIVE
    popd # $1
}

DPCPP_ARTIFACT_DIR=sycl_linux_default

repack_artifact $DPCPP_ARTIFACT_DIR

PATH=$WORKDIR/$DPCPP_ARTIFACT_DIR/bin:$PATH

echo "Packing sycl-bench benchmarks"

pack_sycl_bench() {
    echo "Packing with SYCL_IMPL=$1"
    INSTALL_DIR=$WORKDIR/build/install
    ARTIFACT_FILENAME=sycl-bench-$1.tar.gz
    mkdir -p $INSTALL_DIR
    cmake $SYCL_BENCH_DIR -GNinja -Bbuild \
          -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
          -DSYCL_IMPL=$1 -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR
    cmake --build build --target install
    echo "Replacing bin/run-suite with MLIR version"
    cp -f $SYCL_BENCH_DIR/bin/run-suite $INSTALL_DIR/bin
    tar -I gzip -cf $ARTIFACT_FILENAME -C $INSTALL_DIR .
    rm -rf build
}

pack_sycl_bench LLVM
pack_sycl_bench LLVM-MLIR

echo "Copying files to slurm"
rsync -z \
      $SYCL_BENCH_DIR/bin/slurm-ci-run.batch \
      $SYCL_BENCH_DIR/bin/slurm-run.sh \
      sycl-bench-LLVM.tar.gz \
      sycl-bench-LLVM-MLIR.tar.gz \
      llvm_sycl.tar.gz \
      $SLURM_DESTINATION:~

echo "Running benchmarks on slurm machine"
ssh $SLURM_DESTINATION ./slurm-run.sh

echo "Copying results from slurm"
rsync -z $SLURM_DESTINATION:~/sycl-bench-res/* $SYCL_BENCH_CI_RESULTS_DIR/results

popd # $WORKDIR
