#!/bin/bash -l
#SBATCH --job-name=fenicsx-run
#SBATCH --partition=defq
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=64
#SBATCH --cpus-per-task=1
#SBATCH --time=01:00:00
#SBATCH --output=%x-%j.log
#
# Example job script for the fenicsx-main-241026 environment.
# Usage: sbatch run-example.sh my_script.py [args...]

module use /cm/shared/spack-modules/modulefiles
module load spack
spack env activate fenicsx-main-241026

# FFCx/dolfinx JIT cache on node-local disk (one per job)
export XDG_CACHE_HOME=/tmp/$USER/fenics-cache-$SLURM_JOB_ID
# Use InfiniBand through UCX
export OMPI_MCA_pml=ucx

# mpirun (OpenMPI 5 / PRRTE) picks up the Slurm allocation and binds each rank
# to a core by default -- important here since Slurm does not confine jobs to
# their cores on defq. `srun --mpi=pmix --cpu-bind=cores python ...` also works.
mpirun python "$@"
