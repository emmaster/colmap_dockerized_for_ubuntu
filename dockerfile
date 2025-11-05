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






# Start from the chosen CUDA-enabled COLMAP base image
FROM graffitytech/colmap:3.9-cuda12.2.2-devel-ubuntu22.04

LABEL maintainer="fullstability@gmail.com"
ENV DEBIAN_FRONTEND=noninteractive
ENV QT_QPA_PLATFORM=offscreen

# --- 1) Consolidate Dependency Installation and CMake Upgrade ---
# Many dependencies are likely already present in the COLMAP base image, 
# but we install the rest for GLOMAP and upgrade CMake in one layer.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Essential tools and GLOMAP-specific dependencies
        ffmpeg \
        bash \
        git \
        wget \
        ca-certificates \
        gpg \
        ninja-build \
        libboost-all-dev \
        libopencv-dev \
        libglew-dev \
        qtbase5-dev \
        libqt5opengl5-dev \
        libcgal-dev \
        libatlas-base-dev \
        libsuitesparse-dev && \
    
    # --- CMake Upgrade (Required for latest COLMAP/GLOMAP features) ---
    # Add Kitware repository key
    wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/kitware.gpg && \
    # Add the Kitware repository for Ubuntu 22.04
    echo "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/kitware.list && \
    
    # Install latest CMake and perform final cleanup
    apt-get update && \
    apt-get install -y --no-install-recommends cmake && \
    rm -rf /var/lib/apt/lists/*
    
# --- 2) Build and Install GLOMAP (Utilizing CUDA Base) ---

# Set minimal parallelism to avoid out-of-memory errors on small builders
ENV CMAKE_BUILD_PARALLEL_LEVEL=1

RUN git clone --depth 1 https://github.com/colmap/glomap.git /opt/glomap && \
    
    # Use -DCUDA_ENABLED=ON to utilize the CUDA libraries present in the base image.
    # We keep -DOPENGL_ENABLED=OFF since it's a headless server.
    cmake -S /opt/glomap -B /opt/glomap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF && \
      
    cmake --build /opt/glomap/build && \
    cmake --install /opt/glomap/build && \
    
    # Cleanup build files to reduce final image size
    rm -rf /opt/glomap

# --- 3) Final Execution Setup ---
COPY ./src /src
WORKDIR /src
RUN chmod +x ./action
ENTRYPOINT ["./action"]