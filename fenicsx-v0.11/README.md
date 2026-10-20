# FEniCSx 0.11 Spack environment (`fenicsx-v011`)

## Use it

```bash
module use /cm/shared/spack-modules/modulefiles
module load spack
spack env activate fenicsx-v011
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
| `repo/`       | small local Spack package overlay (py-nanobind 2.9.2, needed by dolfinx 0.11) |

The installed environment lives in
`/cm/shared/spack-modules/apps/spack/1.1.1/var/spack/environments/fenicsx-v011`
(`spack.yaml` + `spack.lock` = exact record of what was built).

## Rebuild / update

```bash
cd ~/spack-envs/fenicsx-v0.11
sbatch build-env.sh                                  # resume / finish a build
RECONCRETIZE=1 sbatch --export=ALL build-env.sh      # pick up newer package versions
ENV_NAME=fenicsx-v012 sbatch --export=ALL build-env.sh   # new env from an edited spack.yaml
```

Edit `spack.yaml` (e.g. `@0.11` → `@0.12`), and submit. Env names may not contain dots.
If defq is full, `sbatch --cpus-per-task=8 build-env.sh` starts sooner.

## What changed compared with `fenicsx-defq`

* **MPI:** `fenicsx-defq` used OpenMPI 5.0.8 built with `fabrics=none schedulers=none`,
  so inter-node communication went over TCP and there was no Slurm integration.
  Here OpenMPI 5.0.8 is built with `fabrics=ucx,cma schedulers=slurm`, with UCX
  (`+verbs +rdmacm +mlx5_dv +rc +ud +dc`) linked against the system Mellanox OFED
  rdma-core, and the system Slurm 21.08.8 as an external.
* **Why not the system OpenMPI module?** The tutorial recommends the system MPI, but the
  only UCX-enabled one (`openmpi/ofed5.8/gcc/64/4.1.4`) has a broken UCX plugin on the
  compute nodes (`mca_pml_ucx.so` needs `libbfd-2.30-system.so`, which is missing), and
  the other system OpenMPIs have no UCX. Building OpenMPI against the system
  rdma-core/Slurm gets the same interconnect support.
* FEniCSx 0.11 (dolfinx 0.11.0.post0, basix/ffcx 0.11, UFL 2026.1), PETSc 3.24.1
  (+mumps +hypre +superlu-dist), hypre 3.0, SuperLU_DIST 9.1, ADIOS2 2.10.2,
  plus the latest scifem, fenicsx-pulse, fenicsx-beat, fenicsx-ldrb,
  cardiac-geometriesx and gotranx.
* Same compiler (GCC 13.4) and target (`x86_64_v3`, which runs on both the defq EPYC
  nodes and the login node) as before. PETSc is 32-bit indices, real, double (as before).

### Updating the scientificcomputing packages

`spack.yaml` excludes the scientificcomputing packages (scifem, fenicsx-pulse/beat/ldrb,
cardiac-geometriesx, gotranx, crossbridge, dolfinx-adjoint, ...) from reuse, so
`sbatch build-env.sh` after editing `spack.yaml`, or `RECONCRETIZE=1 sbatch --export=ALL build-env.sh`,
pulls their newest versions while everything else (MPI, PETSc, dolfinx, VTK, ...) stays as built.

Note: py-dolfinx-adjoint requires `py-pyadjoint@master`, i.e. whatever the pyadjoint git
master branch is at build time; it is not pinned to a release.
