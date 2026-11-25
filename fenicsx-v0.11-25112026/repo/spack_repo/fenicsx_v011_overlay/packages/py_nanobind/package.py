# Local overlay: the builtin repo pinned to Spack 1.1 (releases/v2025.11) stops at
# nanobind 2.8.0, but dolfinx 0.11 requires py-nanobind@2.9.2:.
# Remove this overlay once the builtin repo ships >= 2.9.2.

from spack_repo.builtin.packages.py_nanobind.package import PyNanobind as BuiltinPyNanobind

from spack.package import *


class PyNanobind(BuiltinPyNanobind):
    version(
        "2.9.2", tag="v2.9.2", commit="116e098cfa96effca2a54e32e0ce5b93abe25393", submodules=True
    )
