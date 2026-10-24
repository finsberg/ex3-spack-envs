# FEniCSx main Spack environment (`fenicsx-main-241026`)

Development snapshot set up 24.10.2026: dolfinx, basix, ffcx and UFL from their git
`main` branches, plus scifem and io4dolfinx from `main`. Compiler, MPI stack (OpenMPI +
UCX/InfiniBand + Slurm), PETSc and the other packages are the same as in
[`fenicsx-v0.11`](../fenicsx-v0.11/README.md) and are reused from that build. The
cardiac/biomechanics packages (cardiac-geometriesx, fenicsx-beat/pulse/ldrb, crossbridge,
gotranx, dolfinx-adjoint) are not included.

## Use it

```bash
module use /cm/shared/spack-modules/modulefiles
module load spack
spack env activate fenicsx-main-241026
```

In a Slurm job, put the JIT cache on node-local disk:

```bash
export XDG_CACHE_HOME=/tmp/$USER/fenics-cache-$SLURM_JOB_ID
```

Launch with `mpirun` inside the job (see `run-example.sh`):

```bash
export OMPI_MCA_pml=ucx      # InfiniBand via UCX
mpirun python my_script.py   # uses the Slurm allocation, binds ranks to cores
```

`srun --mpi=pmix --cpu-bind=cores python my_script.py` also works. Always bind ranks
to cores (mpirun does by default): Slurm does not confine jobs to their cores on defq,
and unbound ranks gave 2-3x worse on-node latency in tests.

## Files

| file          | purpose |
|---------------|---------|
| `spack.yaml`  | environment definition (specs, compiler, MPI stack, externals) |
| `build-env.sh`| create/update + concretize + install + smoke tests; `sbatch build-env.sh` |
| `run-example.sh` | example job script |
| `tests/test-2node.sh` | 2-node check: UCX vs TCP ping-pong + dolfinx Poisson (`cd tests; sbatch test-2node.sh`) |
| `repo/`       | small local Spack package overlay (py-nanobind 2.9.2 and py-scikit-build-core 1.0.3, needed by dolfinx main) |

The installed environment lives in
`/cm/shared/spack-modules/apps/spack/1.1.1/var/spack/environments/fenicsx-main-241026`
(`spack.yaml` + `spack.lock` = exact record of what was built).

## Rebuild / update

```bash
cd ~/spack-envs/fenicsx-main-241026
sbatch build-env.sh                                  # resume / finish a build
RECONCRETIZE=1 sbatch --export=ALL build-env.sh      # move to the current heads of main
```

`spack.yaml` excludes the packages built from `main` (dolfinx, basix, ffcx, UFL, scifem,
io4dolfinx, fenicsx-compat) from reuse, so `RECONCRETIZE=1` rebuilds them from the
current heads of their `main` branches, while everything else (MPI, PETSc, VTK, ...)
stays as built. Without `RECONCRETIZE=1` the commits recorded in `spack.lock` are kept.

For a new dated snapshot, copy this directory and submit with a new name, e.g.
`ENV_NAME=fenicsx-main-011126 sbatch --export=ALL build-env.sh`. Env names may not
contain dots. If defq is full, `sbatch --cpus-per-task=8 build-env.sh` starts sooner.
