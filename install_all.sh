#!/usr/bin/env bash
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

#N.B: this install script allows you to run main_slam.py and all the scripts 

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

ROOT_DIR="$SCRIPT_DIR_"
SCRIPTS_DIR="$ROOT_DIR/scripts"

# ====================================================
# import the bash utils 
. "$ROOT_DIR"/bash_utils.sh 

# ====================================================

STARTING_DIR=`pwd`
cd "$ROOT_DIR"

#set -e

# if we are not under docker
if [ ! -f /.dockerenv  ]; then 
    echo "Insert your sudo password (if prompted)..."
    keep_sudo_alive
fi
# Ensure the sudo background process is killed when the script exits
trap stop_sudo_alive EXIT

# Check if conda is installed
if command -v conda &> /dev/null; then
    CONDA_INSTALLED=true
else
    CONDA_INSTALLED=false
fi

if [[ -n "$PIXI_PROJECT_NAME" ]]; then
    PIXI_ACTIVATED=true
else
    PIXI_ACTIVATED=false
fi

# check if a pixi environment has been created in the repo
if [ -d "$ROOT_DIR/.pixi" ]; then
    PIXI_INSTALLED=true
else
    PIXI_INSTALLED=false
fi

# load the local environment file (install_all_pixi.sh sets USE_PIXI=1 in .env)
if [ -f "$ROOT_DIR/.env" ]; then
    . "$ROOT_DIR/.env"
fi

print_blue '================================================'
print_blue "Installing pySLAM"
print_blue '================================================'

# NOTE: when inside a pixi environment, pixi gets the highest priority (even if conda is installed).
if [ "$PIXI_ACTIVATED" = true ]; then
    print_blue "Installing pySLAM by using pixi"
    . "$SCRIPTS_DIR"/install_all_pixi.sh
elif [ "$USE_PIXI" = "1" ]; then
    print_red "pixi is the chosen environment (USE_PIXI=1 is set in $ROOT_DIR/.env) but it is not activated!"
    print_red "Run the following command and then re-run ./install_all.sh:"
    print_red "    pixi shell"
    print_red "If you want to use another environment, remove the file $ROOT_DIR/.env"
    exit 1
elif [ "$CONDA_INSTALLED" = true ]; then
    print_blue "Installing pySLAM by using conda"
    . "$SCRIPTS_DIR"/install_all_conda.sh
elif [ "$PIXI_INSTALLED" = true ]; then
    print_red "A pixi environment has been found in $ROOT_DIR/.pixi but it is not activated!"
    print_red "Run the following command and then re-run ./install_all.sh:"
    print_red "    pixi shell"
    exit 1
else
    print_blue "Installing pySLAM by using venv"
    . "$SCRIPTS_DIR"/install_all_venv.sh
fi

print_blue '================================================'
print_blue "Building and installing pyslam C++ core"
print_blue '================================================'
# NOTE: activation of pySLAM python environment has been done in one of the sourced scripts: 
# install_all_conda.sh, install_all_pixi.sh, install_all_venv.sh
"$ROOT_DIR"/build_cpp_core.sh

cd "$STARTING_DIR"