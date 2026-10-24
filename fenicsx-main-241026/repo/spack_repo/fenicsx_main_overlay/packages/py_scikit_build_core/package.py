# Local overlay: the builtin repo pinned to Spack 1.1 (releases/v2025.11) stops at
# scikit-build-core 0.11.5, but dolfinx main requires py-scikit-build-core@1:.
# Version and dependencies taken from the builtin develop branch (ac09262544).
# Remove this overlay once the builtin repo ships >= 1.0.

from spack_repo.builtin.packages.py_scikit_build_core.package import (
    PyScikitBuildCore as BuiltinPyScikitBuildCore,
)

from spack.package import *


class PyScikitBuildCore(BuiltinPyScikitBuildCore):
    version("1.0.3", sha256="a4d7a05978ee37975c37743510c8991e2debce7ef83afb0a07c0c576fd4f16e8")

    depends_on("py-hatchling@1.24:", when="@0.12:", type="build")
    depends_on("py-hatch-vcs@0.4:", when="@0.12:", type="build")
    depends_on("py-pathspec@0.12.0:", when="@0.12.2:", type=("build", "run"))
    depends_on("py-typing-extensions@4:", when="@0.12.2: ^python@:3.10", type=("build", "run"))
