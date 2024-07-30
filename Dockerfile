FROM nvidia/cuda:12.3.2-devel-ubuntu22.04

RUN apt-get update -y && \
    apt-get install -y wget nano git

# Install cmake 3.30.1
RUN \
    cd /opt && \
    wget https://github.com/Kitware/CMake/releases/download/v3.30.1/cmake-3.30.1-linux-x86_64.sh && \
    bash cmake-3.30.1-linux-x86_64.sh --skip-license && \
    ln -s /opt/bin/cmake /usr/local/bin/

WORKDIR /app

# ENTRYPOINT ["ls", "-alh"]
ENTRYPOINT ["./scripts/build-headless.sh"]
