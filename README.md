# BrickFormer

BrickFormer is a tool for converting a 3D model into a LEGO construction.

<p align="center">
  <img src="https://github.com/user-attachments/assets/ba24c962-cca4-4b60-a6a2-7abd56932262" alt="R2-D2 Preview" />
</p>

To use the tool,
you can either build it from source, or download the pre-built version at https://brickformer.io/.

## Requirements

- [VCPKG](https://learn.microsoft.com/en-us/vcpkg/get_started/get-started?pivots=shell-bash#1---set-up-vcpkg). Make sure the `VCPKG_ROOT` environment variable is set to the installation path
- A NVIDIA GPU with Compute Capability >=7.5
- CUDA toolkit >=12.6
- g++ >=13

> These are the versions with which I was developing locally,
> newer (or possibly older) versions could work too.

## Build from source

Encouraged, as it would provide you with the premium license 😉

##### Linux and Windows x86

```sh
# Clone the repository
git clone https://github.com/loryruta/brickformer
cd brickformer
git submodule update --init --recursive

# Configure the project for building
mkdir build
cd build
cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake

# Build BrickFormer
cmake --build . --target BrickFormer -j

# Run it
cd src
./BrickFormer
```
