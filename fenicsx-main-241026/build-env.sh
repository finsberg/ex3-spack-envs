#!/bin/bash -l
#SBATCH --job-name=build-fenicsx-main-241026
#SBATCH --partition=defq
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=2-00:00:00
#SBATCH --output=build-%x-%j.log
#
# Build (or rebuild / update) the FEniCSx Spack environment on the eX3 cluster.
#
# Usage
#   sbatch build-env.sh                    # build in a Slurm job (recommended; survives logout)
#   bash   build-env.sh                    # build in the current shell
#
# Settings are taken from environment variables, e.g.
#   ENV_NAME=fenicsx-v012 sbatch --export=ALL build-env.sh
#
#   ENV_NAME       name of the Spack environment        (default: fenicsx-main-241026)
#   SPACK_YAML     environment definition to use        (default: spack.yaml next to this script)
#   UPDATE_REPOS   1 = `spack repo update` the git repos first (default: 1)
#   RECONCRETIZE   1 = re-concretize even if a spack.lock exists (default: 0)
#   FRESH          1 = concretize with --fresh (ignore installed packages; default: 0)
#   JOBS           parallel build jobs (default: $SLURM_CPUS_PER_TASK or 16)
#   RUN_TESTS      1 = run the smoke tests after the install (default: 1)
#
# Re-running is safe: Spack skips everything that is already installed, so after
# a failure just fix the problem and submit again.

set -euo pipefail

# --- locate this script's directory (sbatch copies the script to a spool dir) --
if [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/spack.yaml" ]]; then
    SCRIPT_DIR="${SLURM_SUBMIT_DIR}"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

ENV_NAME="${ENV_NAME:-fenicsx-main-241026}"
SPACK_YAML="${SPACK_YAML:-${SCRIPT_DIR}/spack.yaml}"
UPDATE_REPOS="${UPDATE_REPOS:-1}"
RECONCRETIZE="${RECONCRETIZE:-0}"
FRESH="${FRESH:-0}"
JOBS="${JOBS:-${SLURM_CPUS_PER_TASK:-16}}"
RUN_TESTS="${RUN_TESTS:-1}"

log() { echo -e "\n[$(date '+%F %T')] === $* ==="; }

log "Host $(hostname), ${JOBS} build jobs, env '${ENV_NAME}', definition ${SPACK_YAML}"

# --- sanity checks: system libraries UCX / OpenMPI build against -------------
for f in /usr/include/infiniband/verbs.h /usr/include/infiniband/mlx5dv.h \
         /usr/include/rdma/rdma_cma.h /cm/shared/apps/slurm/21.08.8/include/slurm/slurm.h; do
    [[ -e "$f" ]] || { echo "ERROR: missing $f on $(hostname)"; exit 1; }
done

# --- Spack ------------------------------------------------------------------
module use /cm/shared/spack-modules/modulefiles
module load spack
spack --version

# Build stages go to $TMPDIR/$USER/spack-stage (Spack's build_stage config): node-local.
export TMPDIR="${TMPDIR:-/tmp}"

# --- create / update the environment -----------------------------------------
if spack env list | tr -s ' ' '\n' | grep -qxF -- "${ENV_NAME}"; then
    ENV_DIR="$(spack location -e "${ENV_NAME}")"
    if ! cmp -s "${SPACK_YAML}" "${ENV_DIR}/spack.yaml"; then
        log "Updating ${ENV_DIR}/spack.yaml (old one saved as spack.yaml.bak)"
        cp "${ENV_DIR}/spack.yaml" "${ENV_DIR}/spack.yaml.bak"
        cp "${SPACK_YAML}" "${ENV_DIR}/spack.yaml"
        RECONCRETIZE=1
    fi
else
    log "Creating environment ${ENV_NAME}"
    spack env create "${ENV_NAME}" "${SPACK_YAML}"
    ENV_DIR="$(spack location -e "${ENV_NAME}")"
    RECONCRETIZE=1
fi

# Local package overlay (referenced as $env/repo/... in spack.yaml).
if [[ -d "${SCRIPT_DIR}/repo" ]]; then
    rm -rf "${ENV_DIR}/repo"
    cp -r "${SCRIPT_DIR}/repo" "${ENV_DIR}/repo"
fi

spack env activate "${ENV_NAME}"

if [[ "${UPDATE_REPOS}" == 1 ]]; then
    log "Updating git package repositories"
    # builtin is pinned to the Spack release branch; only update the FEniCS ones.
    # Discard regenerated *.pyc files that upstream accidentally committed (they block
    # the rebase), and don't abort the build if an update still fails.
    for r in fenics scientificcomputing; do
        rdir="$(spack repo list 2>/dev/null | awk -v n="$r" '$2==n {print $4}')"
        [[ -n "$rdir" ]] && git -C "$rdir" checkout -- ':(glob)**/*.pyc' 2>/dev/null || true
        spack repo update "$r" || echo "WARNING: could not update repo $r, using current checkout"
    done
fi
spack repo list

# --- concretize ---------------------------------------------------------------
if [[ "${RECONCRETIZE}" == 1 || ! -f "${ENV_DIR}/spack.lock" ]]; then
    log "Concretizing"
    CONC_ARGS=(--force)
    [[ "${FRESH}" == 1 ]] && CONC_ARGS+=(--fresh)
    spack concretize "${CONC_ARGS[@]}" | tee "${ENV_DIR}/concretize.log"
else
    log "Using existing spack.lock (set RECONCRETIZE=1 to redo)"
fi

# --- install ------------------------------------------------------------------
log "Installing"
spack install --jobs "${JOBS}" --show-log-on-error

spack env view regenerate
spack env deactivate

# --- smoke tests ----------------------------------------------------------------
if [[ "${RUN_TESTS}" == 1 ]]; then
    log "Smoke tests"
    spack env activate "${ENV_NAME}"
    export XDG_CACHE_HOME="${TMPDIR}/${USER}/fenics-cache-build-${SLURM_JOB_ID:-$$}"

    echo "--- OpenMPI transports (expect pml ucx, ras/plm slurm):"
    ompi_info | grep -E "MCA (pml|btl|ras|plm)" || true

    echo "--- Python imports:"
    python - <<'EOF'
import dolfinx, basix, ffcx, ufl, petsc4py, mpi4py, adios2, h5py, pyvista, numba, scipy
import scifem, io4dolfinx
from petsc4py import PETSc
print("dolfinx", dolfinx.__version__, "git", dolfinx.git_commit_hash)
print("basix", basix.__version__, "ffcx", ffcx.__version__, "ufl", ufl.__version__)
print("scifem", scifem.__version__, "io4dolfinx", io4dolfinx.__version__)
print("PETSc", PETSc.Sys.getVersion(), "ScalarType", PETSc.ScalarType)
print("dolfinx has_petsc", dolfinx.has_petsc, "has_adios2", dolfinx.has_adios2,
      "has_superlu_dist", getattr(dolfinx, "has_superlu_dist", "n/a"))
print("MPI:", mpi4py.MPI.Get_library_version().splitlines()[0])
EOF

    echo "--- Parallel Poisson (4 ranks, mpirun):"
    TESTPY="$(mktemp --suffix=.py)"
    cat > "${TESTPY}" <<'EOF'
from mpi4py import MPI
import numpy as np, ufl
from dolfinx import mesh, fem
from dolfinx.fem.petsc import LinearProblem
comm = MPI.COMM_WORLD
msh = mesh.create_unit_cube(comm, 24, 24, 24)
V = fem.functionspace(msh, ("Lagrange", 1))
facets = mesh.locate_entities_boundary(msh, 2, lambda x: np.full(x.shape[1], True))
bc = fem.dirichletbc(0.0, fem.locate_dofs_topological(V, 2, facets), V)
u, v = ufl.TrialFunction(V), ufl.TestFunction(V)
a = ufl.inner(ufl.grad(u), ufl.grad(v)) * ufl.dx
L = ufl.inner(1.0, v) * ufl.dx
for pc in ("hypre", "lu"):
    opts = {"ksp_type": "cg", "pc_type": "hypre", "ksp_rtol": 1e-10} if pc == "hypre" else \
           {"ksp_type": "preonly", "pc_type": "lu", "pc_factor_mat_solver_type": "mumps"}
    uh = LinearProblem(a, L, bcs=[bc], petsc_options=opts, petsc_options_prefix=f"t{pc}_").solve()
    n = np.sqrt(msh.comm.allreduce(fem.assemble_scalar(fem.form(uh**2 * ufl.dx)), op=MPI.SUM))
    if comm.rank == 0:
        print(f"{pc}: ||u||_L2 = {n:.8f} on {comm.size} ranks")
EOF
    # --oversubscribe: the build job only owns 1 Slurm task
    mpirun -n 4 --oversubscribe --mca pml ucx python "${TESTPY}"
    rm -f "${TESTPY}"
fi

log "Done. Activate with:
    module use /cm/shared/spack-modules/modulefiles
    module load spack
    spack env activate ${ENV_NAME}"
