#!/bin/bash -l
#SBATCH --job-name=test-fenicsx-main-241026
#SBATCH --partition=defq
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=test-2node-%j.log
#
# Multi-node check of the fenicsx-main-241026 environment:
#   1. inter-node ping-pong over UCX (InfiniBand) vs TCP
#   2. dolfinx Poisson solve on 8 ranks over 2 nodes, via mpirun and srun
# Usage (from this directory): sbatch test-2node.sh

set -u
module use /cm/shared/spack-modules/modulefiles
module load spack
spack env activate fenicsx-main-241026
export XDG_CACHE_HOME=/tmp/$USER/fenics-cache-$SLURM_JOB_ID
cd "${SLURM_SUBMIT_DIR}"

echo "=== nodes: $SLURM_JOB_NODELIST"
mpicc -O2 -o pingpong pingpong.c

echo "=== ping-pong between nodes, UCX (expect ~1-2 us, several GB/s)"
mpirun -n 2 --map-by ppr:1:node --mca pml ucx -x UCX_LOG_LEVEL=info ./pingpong 2>&1 \
    | grep -E "rank|B  lat|UCX  INFO|rror" | head -20

echo "=== ping-pong between nodes, TCP for comparison"
mpirun -n 2 --map-by ppr:1:node --mca pml ob1 --mca btl self,tcp ./pingpong 2>&1 | grep -E "B  lat|rror"

echo "=== dolfinx Poisson, 8 ranks on 2 nodes, mpirun"
cat > poisson_test.py <<'EOF'
from mpi4py import MPI
import numpy as np, ufl, dolfinx
from dolfinx import mesh, fem
from dolfinx.fem.petsc import LinearProblem
comm = MPI.COMM_WORLD
msh = mesh.create_unit_cube(comm, 40, 40, 40)
V = fem.functionspace(msh, ("Lagrange", 1))
facets = mesh.locate_entities_boundary(msh, 2, lambda x: np.full(x.shape[1], True))
bc = fem.dirichletbc(0.0, fem.locate_dofs_topological(V, 2, facets), V)
u, v = ufl.TrialFunction(V), ufl.TestFunction(V)
a = ufl.inner(ufl.grad(u), ufl.grad(v)) * ufl.dx
L = ufl.inner(1.0, v) * ufl.dx
t = MPI.Wtime()
problem = LinearProblem(a, L, bcs=[bc], petsc_options_prefix="p_",
                        petsc_options={"ksp_type": "cg", "pc_type": "hypre", "ksp_rtol": 1e-10})
uh = problem.solve()
n = np.sqrt(comm.allreduce(fem.assemble_scalar(fem.form(uh**2 * ufl.dx)), op=MPI.SUM))
hosts = comm.gather(MPI.Get_processor_name())
if comm.rank == 0:
    print(f"dolfinx {dolfinx.__version__}: ||u||_L2 = {n:.8f}, {V.dofmap.index_map.size_global} dofs, "
          f"{comm.size} ranks on {sorted(set(hosts))}, "
          f"{problem.solver.getIterationNumber()} CG its, {MPI.Wtime() - t:.2f} s")
EOF
mpirun --mca pml ucx python poisson_test.py

echo "=== same with srun --mpi=pmix"
OMPI_MCA_pml=ucx srun --mpi=pmix --cpu-bind=cores python poisson_test.py
rm -f poisson_test.py
