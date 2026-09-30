#!/usr/bin/env bash
# Author: Luigi Freda 
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

#set -e

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

ROOT_DIR="$SCRIPT_DIR_/.."
SCRIPTS_DIR="$ROOT_DIR/scripts"

# ====================================================
# import the bash utils 
. "$ROOT_DIR"/bash_utils.sh 

# ====================================================

STARTING_DIR=`pwd`  
cd "$ROOT_DIR"  

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    version=$(lsb_release -a 2>&1)  # ubuntu version
else 
    version=$OSTYPE
    echo "OS: $version"
fi

# check if we have external options
EXTERNAL_OPTIONS=$@
if [[ -n "$EXTERNAL_OPTIONS" ]]; then
    echo "external option: $EXTERNAL_OPTIONS" 
fi

EXTERNAL_OPTIONS="$EXTERNAL_OPTIONS -DCMAKE_POLICY_VERSION_MINIMUM=3.5"


# Check if conda is installed
if command -v conda &> /dev/null; then
    echo "Conda is installed"
    CONDA_INSTALLED=true
else
    #echo "Conda is not installed"
    CONDA_INSTALLED=false
fi

# Check if pixi is activated
if [[ -n "$PIXI_PROJECT_NAME" ]]; then
    PIXI_ACTIVATED=true
    echo "Pixi environment detected: $PIXI_PROJECT_NAME"

    source "$SCRIPTS_DIR/pixi_python_config.sh"
else
    PIXI_ACTIVATED=false
fi

# ====================================================

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ubuntu_version=$(lsb_release -rs | cut -d. -f1)
else
    ubuntu_version=""
fi

# Check if CC is set and available, otherwise use default gcc
if command -v "$CC" &> /dev/null; then
    gcc_version=$($CC -dumpversion | cut -d. -f1)
elif command -v gcc &> /dev/null; then
    gcc_version=$(gcc -dumpversion | cut -d. -f1)
else
    print_red "Error: No C compiler found. Please install gcc or a equivalent compiler."
fi
echo "gcc_version: $gcc_version"

if [[ "$CONDA_INSTALLED" == true && "$ubuntu_version" == "20" && "$gcc_version" == 11 ]]; then
    print_blue "Setting GCC and G++ to version 9"
    export CC=/usr/bin/gcc-9
    export CXX=/usr/bin/g++-9
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Make sure we don't accidentally use a Linux cross-compiler or Linux sysroot from conda
    unset CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS SDKROOT CONDA_BUILD_SYSROOT CONDA_BUILD_CROSS_COMPILATION

    # Ask Xcode for the proper macOS SDK path (fallback to default if unavailable)
    MAC_SYSROOT=$(xcrun --show-sdk-path 2>/dev/null || echo "")

    MAC_OPTIONS="-DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++"

    echo "Using MAC_OPTIONS for cpp build: $MAC_OPTIONS"
fi

print_blue '================================================'
print_blue "Installing gtsam from source"
print_blue '================================================'

# Prefer the active conda/venv python (set by install_all_conda.sh via pyenv-activate.sh)
if [[ -n "$CONDA_PREFIX" && -x "$CONDA_PREFIX/bin/python" ]]; then
    PYTHON_EXE="$CONDA_PREFIX/bin/python"
else
    PYTHON_EXE=$(which python)
fi
echo "Using PYTHON_EXE: $PYTHON_EXE"

PYTHON_VERSION=$($PYTHON_EXE -c "import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")")


WITH_MARCH_NATIVE=ON
if [[ "$OSTYPE" == darwin* ]]; then
    WITH_MARCH_NATIVE=OFF
fi
if [[ "$PIXI_ACTIVATED" == true ]]; then
    WITH_MARCH_NATIVE=OFF
fi
echo "WITH_MARCH_NATIVE: $WITH_MARCH_NATIVE"

# gtwrap (GTSAM Python bindings) needs pyparsing at build time (normally installed by install_pip3_packages.sh)
ensure_python_package "$PYTHON_EXE" "pyparsing>=2.4.6" pyparsing || exit 1

cd thirdparty
if [ ! -d gtsam_local ]; then
	git clone https://github.com/borglab/gtsam.git gtsam_local
    #git fetch --all --tags # to fetch tags 
    cd gtsam_local
    git checkout tags/4.2a9   
    git apply ../gtsam.patch
    cd .. 
fi
cd gtsam_local
make_buid_dir
TARGET_GTSAM_LIB="install/lib/libgtsam.so"
if [[ "$OSTYPE" == darwin* ]]; then 
    TARGET_GTSAM_LIB="install/lib/libgtsam.dylib"
fi
if [[ ! -f "$TARGET_GTSAM_LIB" ]]; then
	cd build
    # NOTE: gtsam has some issues when compiling with march=native option!
    # https://groups.google.com/g/gtsam-users/c/jdySXchYVQg
    # https://bitbucket.org/gtborg/gtsam/issues/414/compiling-with-march-native-results-in 
    GTSAM_OPTIONS="-DGTSAM_USE_SYSTEM_EIGEN=ON -DGTSAM_BUILD_WITH_MARCH_NATIVE=$WITH_MARCH_NATIVE -DGTSAM_BUILD_PYTHON=ON -DGTSAM_BUILD_TESTS=OFF -DGTSAM_BUILD_EXAMPLES=OFF" 
    if [[ "$version" == *"24.04"* ]] ; then
        # Ubuntu 24.04 requires CMake 3.22 or higher
        GTSAM_OPTIONS+=" -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    fi
    GTSAM_OPTIONS+=" -DGTSAM_THROW_CHEIRALITY_EXCEPTION=OFF -DCMAKE_PYTHON_EXECUTABLE=$PYTHON_EXE -DGTSAM_PYTHON_VERSION=$PYTHON_VERSION"
    if [[ "$OSTYPE" == darwin* ]]; then
        GTSAM_OPTIONS+=" -DGTSAM_WITH_TBB=OFF"
    fi 

    # Under pixi the conda gcc links with --sysroot, which hides both /usr/lib and the
    # pixi env lib dir; let the linker resolve shared deps (e.g. tbb, suitesparse) from the env.
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        GTSAM_PIXI_LIB_DIR=""
        if [ -d "$ROOT_DIR/.pixi/envs/default/lib" ]; then
            GTSAM_PIXI_LIB_DIR="$ROOT_DIR/.pixi/envs/default/lib"
        elif [ -d ".pixi/envs/default/lib" ]; then
            GTSAM_PIXI_LIB_DIR=".pixi/envs/default/lib"
        fi
        if [ -n "$GTSAM_PIXI_LIB_DIR" ]; then
            GTSAM_OPTIONS="$GTSAM_OPTIONS \
                -DCMAKE_PREFIX_PATH=$(dirname "$GTSAM_PIXI_LIB_DIR") \
                -DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath-link,$GTSAM_PIXI_LIB_DIR \
                -DCMAKE_SHARED_LINKER_FLAGS=-Wl,-rpath-link,$GTSAM_PIXI_LIB_DIR \
                -DCMAKE_MODULE_LINKER_FLAGS=-Wl,-rpath-link,$GTSAM_PIXI_LIB_DIR"
            echo "Added pixi env lib dir to linker search: $GTSAM_PIXI_LIB_DIR"
        fi
    fi
    echo GTSAM_OPTIONS: $GTSAM_OPTIONS
    cmake .. -DCMAKE_INSTALL_PREFIX="`pwd`/../install" -DCMAKE_BUILD_TYPE=Release $GTSAM_OPTIONS $EXTERNAL_OPTIONS $MAC_OPTIONS
	make -j $(nproc)
    make install 

    # Now install gtsam python package
    make python-install
else
    # The C++ lib is already built, but the python env may have been (re)created in the meantime
    # (e.g. a fresh pixi env that also ships the conda-forge gtsam bindings). Make sure the
    # installed gtsam python module is the one built here, otherwise gtsam_factors fails to import
    # with: 'referenced unknown base type "gtsam::NonlinearFactor"'.
    LOCAL_GTSAM_PY_LIB=$(ls build/python/gtsam/gtsam*.so 2>/dev/null | head -n 1)
    INSTALLED_GTSAM_PY_LIB=$("$PYTHON_EXE" -c "import gtsam.gtsam as g; print(g.__file__)" 2>/dev/null)
    if [[ -n "$LOCAL_GTSAM_PY_LIB" ]] && ! cmp -s "$LOCAL_GTSAM_PY_LIB" "$INSTALLED_GTSAM_PY_LIB"; then
        print_yellow "The installed gtsam python module is not the local build: reinstalling it"
        cd build
        make python-install
        cd ..
    fi
fi

echo current folder: $(pwd)

cd "$ROOT_DIR"

print_blue '================================================'
print_blue "Building gtsam_factors"
print_blue '================================================'

cd thirdparty
cd gtsam_factors
./build.sh $EXTERNAL_OPTIONS -DWITH_MARCH_NATIVE=$WITH_MARCH_NATIVE

cd "$ROOT_DIR"

cd "$STARTING_DIR"