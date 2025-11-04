# # ---------- Builder: compile COLMAP with CUDA 13 ----------
# FROM nvidia/cuda:13.0.0-devel-ubuntu22.04 AS builder

# ARG DEBIAN_FRONTEND=noninteractive
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     git cmake build-essential \
#     libeigen3-dev libboost-all-dev \
#     libfreeimage-dev libgoogle-glog-dev libgflags-dev \
#     libglew-dev libsqlite3-dev \
#     libsuitesparse-dev libceres-dev \
#     qtbase5-dev libqt5opengl5-dev \
#  && rm -rf /var/lib/apt/lists/*

# # Get COLMAP (use a tag if you want a fixed version, e.g., v3.9)
# WORKDIR /opt
# RUN git clone --depth 1 https://github.com/colmap/colmap.git
# WORKDIR /opt/colmap
# RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -D CUDA_ENABLED=ON
# RUN cmake --build build --target colmap --parallel
# RUN cmake --install build --prefix /usr/local

# # ---------- Runtime: slim image with CUDA 13 runtime ----------
# FROM nvidia/cuda:13.0.0-runtime-ubuntu22.04 AS runtime

# ARG DEBIAN_FRONTEND=noninteractive
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     ffmpeg bash libfreeimage3 libgoogle-glog0v5 libgflags2.2 \
#     libglew2.2 libsqlite3-0 libboost-filesystem1.74.0 libboost-program-options1.74.0 \
#     libboost-serialization1.74.0 libboost-system1.74.0 \
#     qtbase5-dev libqt5opengl5 \
#  && rm -rf /var/lib/apt/lists/*

# # Bring the compiled COLMAP over
# COPY --from=builder /usr/local/ /usr/local/


# ... The rest of your Dockerfile instructions for installing COLMAP ...

# FROM colmap/colmap
FROM graffitytech/colmap:3.9-cuda12.2.2-devel-ubuntu22.04
# FROM graffitytech/colmap:3.8-cpu-ubuntu22.04

LABEL maintainer="fullstability@gmail.com"
RUN apt update && apt install -y ffmpeg
RUN apt-get update && apt-get install -y bash
ENV QT_QPA_PLATFORM=offscreen


COPY ./src /src
WORKDIR /src
RUN chmod +x ./action
ENTRYPOINT ["./action"]