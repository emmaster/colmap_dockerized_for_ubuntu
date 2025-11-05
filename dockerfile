
# CUDA dev base
FROM nvidia/cuda:12.2.2-devel-ubuntu22.04

LABEL maintainer="fullstability@gmail.com"
ENV DEBIAN_FRONTEND=noninteractive
ENV QT_QPA_PLATFORM=offscreen
ENV PATH="/usr/local/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
# Optional: set your GPU arch for smaller/faster CUDA builds (86=RTX30xx, 89=RTX40xx)
ARG CUDA_ARCH=89
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# --- 1) System deps + latest CMake (no GUI/GL since headless) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg bash lsb-release git wget ca-certificates gpg \
        build-essential ninja-build pkg-config \
        # math / linear algebra / sparse
        libatlas-base-dev libsuitesparse-dev libmetis-dev \
        # logging / flags
        libgflags-dev libgoogle-glog-dev \
        # core libs
        libeigen3-dev libflann-dev libsqlite3-dev libcgal-dev \
        # image I/O
        libfreeimage-dev \
        # OpenCV headers (optional but useful)
        libopencv-dev && \
    # Kitware CMake
    wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc \
      | gpg --dearmor -o /etc/apt/trusted.gpg.d/kitware.gpg && \
    echo "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/kitware.list && \
    apt-get update && apt-get install -y --no-install-recommends cmake && \
    rm -rf /var/lib/apt/lists/*

# --- 2) Ceres 2.1.0 (CUDA + SuiteSparse + glog, no miniglog) ---
RUN CERES_VERSION="2.1.0" && \
    git clone --branch "$CERES_VERSION" --depth 1 \
      https://ceres-solver.googlesource.com/ceres-solver /opt/ceres-solver && \
    cmake -S /opt/ceres-solver -B /opt/ceres-solver/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DCERES_USE_CUDA=ON \
      -DMINIGLOG=OFF \
      -DSUITESPARSE=ON \
      -DBUILD_SHARED_LIBS=ON \
      -DBUILD_TESTING=OFF \
      -DBUILD_EXAMPLES=OFF && \
    cmake --build /opt/ceres-solver/build && \
    cmake --install /opt/ceres-solver/build && \
    rm -rf /opt/ceres-solver && ldconfig

# --- 3) FAISS (GPU, shared, no Python) ---
# NOTE: Do NOT install libfaiss-dev from apt (conflicts with our custom build)
RUN git clone --depth 1 https://github.com/facebookresearch/faiss.git /opt/faiss && \
    cmake -S /opt/faiss -B /opt/faiss/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DBUILD_SHARED_LIBS=ON \
      -DFAISS_ENABLE_GPU=ON \
      -DFAISS_ENABLE_PYTHON=OFF \
      -DFAISS_ENABLE_C_API=ON && \
    cmake --build /opt/faiss/build --target install && \
    rm -rf /opt/faiss && ldconfig

# --- 4) COLMAP 3.12.3 (headless, CUDA) ---
RUN git clone --depth 1 -b 3.12.3 https://github.com/colmap/colmap.git /opt/colmap && \
    cmake -S /opt/colmap -B /opt/colmap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF \
      -DGUI_ENABLED=OFF \
      -DBUILD_SHARED_LIBS=ON \
      -DCGAL_ENABLED=ON && \
    cmake --build /opt/colmap/build && \
    cmake --install /opt/colmap/build && \
    rm -rf /opt/colmap && ldconfig

# --- 5) GLOMAP v1.1.0 (headless, CUDA) ---
RUN git clone --depth 1 -b v1.1.0 https://github.com/colmap/glomap.git /opt/glomap && \
    cmake -S /opt/glomap -B /opt/glomap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF && \
    cmake --build /opt/glomap/build && \
    cmake --install /opt/glomap/build && \
    rm -rf /opt/glomap && ldconfig

# --- 6) Final runtime setup ---
COPY ./src /src
WORKDIR /src
RUN chmod +x ./action
ENTRYPOINT ["./action"]