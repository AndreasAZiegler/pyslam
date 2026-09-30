# Install under pixi 

Here you can find the instructions to install `pyslam` under `pixi` and a very concise `pixi` primer.

<!-- TOC -->

- [Install under pixi](#install-under-pixi)
  - [Install `pyslam` with pixi](#install-pyslam-with-pixi)
    - [Install pixi](#install-pixi)
    - [Activate pixi shell](#activate-pixi-shell)
    - [Launch the `pyslam` install script](#launch-the-pyslam-install-script)
    - [Launch a main `pyslam` script](#launch-a-main-pyslam-script)
  - [Pixi primer](#pixi-primer)
    - [Initialize a Project](#initialize-a-project)
    - [Add dependancies](#add-dependancies)
    - [Run Commands in Environment](#run-commands-in-environment)
    - [Enter an interactive shell](#enter-an-interactive-shell)
    - [Add specific platform targets](#add-specific-platform-targets)
    - [Remove the local pixi environment](#remove-the-local-pixi-environment)
    - [Table of commands](#table-of-commands)
  - [References](#references)

<!-- /TOC -->

---


## Install `pyslam` with pixi

Currently, pixi support is experimental and may encounter issues with building and linking.

Follow the steps reported below: 

### Install pixi 
```
curl -fsSL https://pixi.sh/install.sh | sh
```

Reference: https://pixi.sh/latest/#installation


### Activate pixi shell 

From the root folder of this repository, run
```bash
pixi shell 
```

### Launch the `pyslam` install script 

Then, from the root folder, run
```bash
./install_all.sh
```

This script will prepare the pixi-dedicated `pyslam` environment, and build the required thirdparty packages. Under the hood, the script `install_all.sh` calls the pixi-specific script `scripts/install_all_pixi.sh`. 

### Launch a main `pyslam` script

Once you have activate the pixi shell in your terminal, you're ready to run any main script.


### Arch Linux

The pixi flow relies on the pixi environment (see `pixi.toml`) instead of installing system packages, so no `pacman`/`apt` packages are required for the build itself.

The C/C++ compiler used by the build (including the OpenCV CUDA compilation with nvcc 12.8) is the conda-forge toolchain shipped in the pixi environment: `gcc_linux-64`/`gxx_linux-64`, pinned to `12.4.*` (a version supported by nvcc 12.8). The system `gcc`/`g++` is only used as a fallback if the pixi compilers are missing.

The conda-forge linker always runs with `--sysroot=<env>/x86_64-conda-linux-gnu/sysroot`, which hides both `/usr/lib` and the pixi env `lib/` from the default library search. The OpenCV and thirdparty build scripts therefore explicitly add the pixi env lib dir to the link path (`-DCMAKE_*_LINKER_FLAGS=-Wl,-rpath-link,$PIXI_LIB_DIR` plus `-DCMAKE_PREFIX_PATH`), so shared dependencies such as `libz.so.1` resolve from the pixi environment instead of the system.

Before running the install script, make sure the base toolchain is present:

```bash
sudo pacman -S --needed base-devel pkgconf
# optional, if you use an NVIDIA GPU (pixi.toml requires CUDA 12.8):
sudo pacman -S --needed nvidia nvidia-utils
```

Then follow the standard flow:

```bash
pixi shell
./install_all.sh
```

If the script complains that the pixi environment is not activated (e.g. `USE_PIXI=1` is set in `.env`), activate it with `pixi shell` and re-run `./install_all.sh`.


--- 

## Pixi primer

###  Initialize a Project

From within your project folder:
```bash
pixi init
```
This creates a pixi.toml (like pyproject.toml) describing your environment.


### Add dependancies 

Conda packages (from conda-forge):
```bash
pixi add numpy scipy matplotlib
```

Pip packages:
```bash
pixi add pip
pixi run pip install opencv-python
```
Then manually edit pixi.toml to reflect pip-installed packages:

```toml
[tool.pixi.pip-dependencies]
opencv-python = "*"
```

### Run Commands in Environment


To test the environement: 
```bash
pixi run python -c "import numpy; print(numpy.__version__)"
pixi run python -c "import cv2; print(cv2.__version__)" 
``` 

Other examples: 
```bash
pixi run python script.py
pixi run jupyter notebook
```

### Enter an interactive shell 

```bash
pixi shell
```
This opens a shell with pixi enviornment variable already set and you don't need anymore to use `pixi run ...<python command>`.


### Add specific platform targets 

Add specific platform targets (e.g., cross-platform builds):
```toml
[tool.pixi]
platforms = ["linux-64", "osx-arm64", "win-64"]
```

### Remove the local pixi environment 

To delete the environment associated with the current project (i.e., clean slate):
```bash
pixi clean --all
``` 

This removes:
- The current environment’s packages
- The build cache
- Any temporary/lock artifacts

You can then rebuild it cleanly with:
```bash
pixi install
```

### Table of commands

This is a recap table:

| Command                     | Description                           |
| --------------------------- | ------------------------------------- |
| `pixi init`                 | Initialize a new project              |
| `pixi add <pkg>`            | Add a dependency                      |
| `pixi install`              | Re-resolve and install dependencies   |
| `pixi run <cmd>`            | Run a command in the environment      |
| `pixi shell`                | Enter an interactive shell            |
| `pixi remove <pkg>`         | Remove a package                      |
| `pixi list`                 | List installed packages               |
| `pixi export --format toml` | Export environment definition as TOML |
| `pixi update`               | Update dependencies and re-lock       |
| `pixi clean --all`          | Remove the local pixi environment     |   


---

## References

- _"Cross-Platform Package Management for Modern C++ Development with Pixi - Ruben Arts - CppCon 2025"_ 
  https://www.youtube.com/watch?v=SQk0lKv2swk