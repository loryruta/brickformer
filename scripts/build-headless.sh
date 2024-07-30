#!/bin/bash

# Script used as the entrypoint of the Docker build image

mkdir docker-build
cd docker-build

cmake .. -DLEGO_BUILDER_NO_VIDEO=ON
cmake --build . --target lego_builder_headless

cp ./src/headless/lego_builder_headless .
