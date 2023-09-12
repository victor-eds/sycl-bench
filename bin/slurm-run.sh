#! /bin/bash -e

WORKDIR=$PWD/WD

echo "Cleaning workspace"
rm -rf $WORKDIR

echo "Initializing workspace"
mkdir -p $WORKDIR
mv slurm-ci-run.batch \
   sycl-bench-LLVM.tar.gz \
   sycl-bench-LLVM-MLIR.tar.gz \
   llvm_sycl.tar.gz \
   $WORKDIR
cd $WORKDIR

echo "Installing SYCL runtime library"
mkdir sycl_linux_default
tar -I gzip -xf llvm_sycl.tar.gz -C sycl_linux_default
rm llvm_sycl.tar.gz

unpack_sycl_bench() {
    SYCL_BENCH_NAME=sycl-bench-$1
    echo "Unpacking $SYCL_BENCH_NAME"
    SYCL_BENCH_ARCHIVE=$SYCL_BENCH_NAME.tar.gz
    mkdir $SYCL_BENCH_NAME
    tar -I gzip -xf $SYCL_BENCH_ARCHIVE -C $SYCL_BENCH_NAME
    rm $SYCL_BENCH_ARCHIVE
}

unpack_sycl_bench LLVM
unpack_sycl_bench LLVM-MLIR

echo "Creating result directories"
mkdir -p ~/sycl-bench-test
mkdir -p ~/sycl-bench-res

echo "Run verification and benchmarks (synchronously)"
sbatch --wait ./slurm-ci-run.batch
