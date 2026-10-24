#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
  MPI_Init(&argc, &argv);
  int r, n; char host[MPI_MAX_PROCESSOR_NAME]; int hl;
  MPI_Comm_rank(MPI_COMM_WORLD, &r); MPI_Comm_size(MPI_COMM_WORLD, &n);
  MPI_Get_processor_name(host, &hl); printf("rank %d/%d on %s\n", r, n, host); fflush(stdout);
  MPI_Barrier(MPI_COMM_WORLD);
  for (long sz = 8; sz <= (1L << 24); sz *= 64) {
    char *buf = malloc(sz); int it = sz > 100000 ? 50 : 2000;
    MPI_Barrier(MPI_COMM_WORLD); double t = MPI_Wtime();
    for (int i = 0; i < it; i++) {
      if (r == 0) { MPI_Send(buf, sz, MPI_CHAR, 1, 0, MPI_COMM_WORLD); MPI_Recv(buf, sz, MPI_CHAR, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE); }
      else if (r == 1) { MPI_Recv(buf, sz, MPI_CHAR, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE); MPI_Send(buf, sz, MPI_CHAR, 0, 0, MPI_COMM_WORLD); }
    }
    t = (MPI_Wtime() - t) / (2.0 * it);
    if (r == 0) printf("%10ld B  latency %8.2f us  bandwidth %8.1f MB/s\n", sz, t * 1e6, sz / t / 1e6);
    free(buf);
  }
  MPI_Finalize();
}
