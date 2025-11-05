# # FROM colmap/colmap
# FROM graffitytech/colmap:3.9-cuda12.2.2-devel-ubuntu22.04
# # FROM graffitytech/colmap:3.8-cpu-ubuntu22.04

# LABEL maintainer="fullstability@gmail.com"
# RUN apt update && apt install -y ffmpeg
# RUN apt-get update && apt-get install -y bash
# ENV QT_QPA_PLATFORM=offscreen


# # Install dependencies for building glomap
# RUN apt-get update && apt-get install -y \
#     git cmake build-essential libboost-all-dev libopencv-dev \
#     libglew-dev qtbase5-dev libqt5opengl5-dev libcgal-dev \
#     libatlas-base-dev libsuitesparse-dev && \
#     rm -rf /var/lib/apt/lists/*

# # Upgrade CMake to >= 3.28 (Kitware repo) and install build deps
# RUN apt-get update && apt-get install -y --no-install-recommends \
#       wget ca-certificates gpg git build-essential cmake-data ninja-build \
#       libboost-all-dev libopencv-dev libglew-dev qtbase5-dev libqt5opengl5-dev \
#       libcgal-dev libatlas-base-dev libsuitesparse-dev && \
#     update-ca-certificates && \
#     wget -q https://apt.kitware.com/kitware-archive.sh && \
#     bash kitware-archive.sh && rm kitware-archive.sh && \
#     apt-get update && apt-get install -y --no-install-recommends cmake && \
#     cmake --version

# # 2) Build glomap with minimal parallelism (j1) and optional feature disables
# #    -DCUDA_ENABLED=OFF and -DOPENGL_ENABLED=OFF help on tiny builders
# ENV CMAKE_BUILD_PARALLEL_LEVEL=1
# RUN git clone --depth 1 https://github.com/colmap/glomap.git /opt/glomap && \
#     cmake -S /opt/glomap -B /opt/glomap/build \
#       -G Ninja \
#       -DCMAKE_BUILD_TYPE=Release \
#       -DCUDA_ENABLED=OFF \
#       -DOPENGL_ENABLED=OFF && \
#     cmake --build /opt/glomap/build && \
#     cmake --install /opt/glomap/build


# COPY ./src /src
# WORKDIR /src
# RUN chmod +x ./action
# ENTRYPOINT ["./action"]




# #======> Ver with GLOMAP didn't work, GLOMAP gives error

# # Start from the chosen CUDA-enabled COLMAP base image
# FROM graffitytech/colmap:3.9-cuda12.2.2-devel-ubuntu22.04

# LABEL maintainer="fullstability@gmail.com"
# ENV DEBIAN_FRONTEND=noninteractive
# ENV QT_QPA_PLATFORM=offscreen

# # --- 1) Consolidated Dependency Installation and CMake Upgrade ---
# RUN apt-get update && \
#     apt-get install -y --no-install-recommends \
#         # CRITICAL FIX: Install lsb-release so $(lsb_release -cs) works
#         lsb-release \
#         # Essential tools and GLOMAP-specific dependencies
#         ffmpeg \
#         bash \
#         git \
#         wget \
#         ca-certificates \
#         gpg \
#         ninja-build \
#         libboost-all-dev \
#         libopencv-dev \
#         libglew-dev \
#         qtbase5-dev \
#         libqt5opengl5-dev \
#         libcgal-dev \
#         libatlas-base-dev \
#         libsuitesparse-dev && \
    
#     # --- CMake Upgrade (Kitware Repo Setup) ---
#     # Add Kitware repository key
#     wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/kitware.gpg && \
#     # Add the Kitware repository (lsb_release now works here)
#     echo "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/kitware.list && \
    
#     # Install latest CMake and perform final cleanup
#     apt-get update && \
#     apt-get install -y --no-install-recommends cmake && \
#     rm -rf /var/lib/apt/lists/*
    
# # --- 2) Build and Install GLOMAP ---
# ENV CMAKE_BUILD_PARALLEL_LEVEL=1

# # This second block should remain the same and will run after the dependencies are fixed
# RUN git clone --depth 1 https://github.com/colmap/glomap.git /opt/glomap && \
#     cmake -S /opt/glomap -B /opt/glomap/build \
#       -G Ninja \
#       -DCMAKE_BUILD_TYPE=Release \
#       -DCUDA_ENABLED=ON \
#       -DOPENGL_ENABLED=OFF && \
#     cmake --build /opt/glomap/build && \
#     cmake --install /opt/glomap/build && \
#     rm -rf /opt/glomap

# # --- 3) Final Execution Setup ---
# COPY ./src /src
# WORKDIR /src
# RUN chmod +x ./action
# ENTRYPOINT ["./action"]



### Final working version with COLMAP and GLOMAP, CUDA enabled

# Use a standard CUDA base image for building
FROM nvidia/cuda:12.2.2-devel-ubuntu22.04

LABEL maintainer="fullstability@gmail.com"
ENV DEBIAN_FRONTEND=noninteractive
ENV QT_QPA_PLATFORM=offscreen
ENV PATH="/usr/local/bin:$PATH"

# --- 1) Install Build and COLMAP/GLOMAP Dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Essential tools
        ffmpeg \
        bash \
        lsb-release \
        git \
        wget \
        ca-certificates \
        gpg \
        build-essential \
        ninja-build \
        # COLMAP/GLOMAP dependencies
        libboost-all-dev \
        libopencv-dev \
        libglew-dev \
        qtbase5-dev \
        libqt5opengl5-dev \
        libcgal-dev \
        libatlas-base-dev \
        libsuitesparse-dev \
        libgflags-dev \
        libgoogle-glog-dev \
        libeigen3-dev \
        libmetis-dev \
        libgtest-dev \
        libflann-dev && \
    
    # --- Install latest CMake (Required) ---
    wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/kitware.gpg && \
    echo "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/kitware.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends cmake && \
    
    # Cleanup
    rm -rf /var/lib/apt/lists/*

# --- NEW STEP: 2) Build and Install Ceres Solver 2.1.0 with CUDA ---
RUN CERES_VERSION="2.1.0" && \
    git clone --branch $CERES_VERSION --depth 1 https://ceres-solver.googlesource.com/ceres-solver /opt/ceres-solver && \
    cmake -S /opt/ceres-solver -B /opt/ceres-solver/build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCUDA=ON \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF && \
    cmake --build /opt/ceres-solver/build && \
    cmake --install /opt/ceres-solver/build && \
    rm -rf /opt/ceres-solver

# --- 3) Build and Install COLMAP 3.12.3 (Library Dependency) ---
# COLMAP will now find the Ceres libraries installed in the previous step
RUN git clone --depth 1 -b 3.12.3 https://github.com/colmap/colmap.git /opt/colmap && \
    cmake -S /opt/colmap -B /opt/colmap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF \
      -DBUILD_GUI=OFF \
      -DBUILD_SHARED_LIBS=ON \
      -DCGAL_ENABLED=ON && \
    cmake --build /opt/colmap/build && \
    cmake --install /opt/colmap/build && \
    rm -rf /opt/colmap

# --- 4) Build and Install GLOMAP 1.1.0 ---
ENV CMAKE_BUILD_PARALLEL_LEVEL=1

RUN git clone --depth 1 -b v1.1.0 https://github.com/colmap/glomap.git /opt/glomap && \
    # The GLOMAP build will find COLMAP/Ceres installed previously
    cmake -S /opt/glomap -B /opt/glomap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF \
      -DBUILD_GUI=OFF && \
    cmake --build /opt/glomap/build && \
    cmake --install /opt/glomap/build && \
    rm -rf /opt/glomap

# --- 5) Final Execution Setup ---
COPY ./src /src
WORKDIR /src
RUN chmod +x ./action
ENTRYPOINT ["./action"]