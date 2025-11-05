
# Use a standard CUDA base image for building
FROM nvidia/cuda:12.2.2-devel-ubuntu22.04

LABEL maintainer="fullstability@gmail.com"
ENV DEBIAN_FRONTEND=noninteractive
ENV QT_QPA_PLATFORM=offscreen
ENV PATH="/usr/local/bin:$PATH"

# CRITICAL FIX: Add /usr/local/lib to the library search path
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

# --- 1) Install All Dependencies and Latest CMake ---
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
        libflann-dev \
        libsqlite3-dev \
        libfreeimage-dev \
        libfaiss-dev && \
    
    # --- Install latest CMake (Required) ---
    wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/kitware.gpg && \
    echo "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/kitware.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends cmake && \
    
    # Final cleanup of apt lists
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------

# --- 2) Build and Install Ceres Solver 2.1.0 with CUDA ---
RUN CERES_VERSION="2.1.0" && \
    git clone --branch $CERES_VERSION --depth 1 https://ceres-solver.googlesource.com/ceres-solver /opt/ceres-solver && \
    cmake -S /opt/ceres-solver -B /opt/ceres-solver/build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCUDA=ON \
        -DCUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda \
        -DMINIGLOG=ON \
        -DLAPACK=ON \
        -DGLOG=ON \
        -DSUITESPARSE=ON \
        -DCUDA_DENSE=ON \
        -DACCELERATE_LAPACK=ON \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF && \
    cmake --build /opt/ceres-solver/build && \
    cmake --install /opt/ceres-solver/build && \
    rm -rf /opt/ceres-solver

# --- NEW STEP: 3) Build and Install FAISS with CUDA ---
RUN git clone --depth 1 https://github.com/facebookresearch/faiss.git /opt/faiss && \
    cmake -S /opt/faiss -B /opt/faiss/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DFAISS_ENABLE_GPU=ON \
      -DFAISS_ENABLE_PYTHON=OFF \
      -DFAISS_ENABLE_C_API=ON && \
    cmake --build /opt/faiss/build --target install && \
    rm -rf /opt/faiss


# ---------------------------------------------------------------------

# --- 4) Build and Install COLMAP 3.12.3 (Library Dependency) ---
RUN git clone --depth 1 -b 3.12.3 https://github.com/colmap/colmap.git /opt/colmap && \
    
    # CRITICAL FIX 1/6 (Cleanup): Remove all conflicting and old fixes
    sed -i '/#include <glog\/logging.h>/d' /opt/colmap/src/colmap/util/logging.h && \
    sed -i '/#include <glog\/raw_logging.h>/d' /opt/colmap/src/colmap/util/logging.h && \
    sed -i '/#define _EQ __COUNTER__/d' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 2/6 (Consolidated Header/Type Fix): Insert necessary headers and type aliases at line 38.
    # We must also correct the LogMessageFatal call to the non-namespaced version.
    sed -i '38i#include <stdint.h>\n#include "glog/logging.h"\n#include <glog/raw_logging.h>\n\nnamespace google { using int32 = int32_t; using int64 = int64_t; }' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 3/6 (Operators): Re-introduce operator counter macros (line 87)
    sed -i '87i#define _EQ __COUNTER__\n#define _NE __COUNTER__\n#define _LE __COUNTER__\n#define _LT __COUNTER__\n#define _GE __COUNTER__\n#define _GT __COUNTER__' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 4/6 (LogMessageFatal Scope): The function is often globally scoped, not in ::google.
    sed -i 's/::google::LogMessageFatal/LogMessageFatal/g' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 5/6 (CHECK_OP_LOG / Operator Punctuation Fix): 
    # This completely replaces the THROW_CHECK_OP macro definition to fix the 'CHECK_OP_LOG' error 
    # and the operator punctuation error simultaneously. It converts all operator checks 
    # to use the standard glog CHECK_OP macros which are defined in the included headers.
    # NOTE: This is a complex sed command to replace lines 94-103 of logging.h
    # Based on a typical COLMAP logging.h (3.12), lines 94-103 contain the THROW_CHECK_OP macros.
    sed -i '94,103c\
#define THROW_CHECK_OP(op, name, val1, val2) \
  RAW_CHECK_OP(op, name, val1, val2, LogMessageFatal) \
\
#define THROW_CHECK(condition) \
  LOG_IF(FATAL, GOOGLE_PREDICT_BRANCH_NOT_TAKEN(!(condition))) << "Check failed: " #condition << ": "\
\
#define THROW_CHECK_EQ(val1, val2) THROW_CHECK_OP(==, _EQ, val1, val2)\
#define THROW_CHECK_NE(val1, val2) THROW_CHECK_OP(!=, _NE, val1, val2)\
#define THROW_CHECK_LE(val1, val2) THROW_CHECK_OP(<=, _LE, val1, val2)\
#define THROW_CHECK_LT(val1, val2) THROW_CHECK_OP(<, _LT, val1, val2)\
#define THROW_CHECK_GE(val1, val2) THROW_CHECK_OP(>=, _GE, val1, val2)\
#define THROW_CHECK_GT(val1, val2) THROW_CHECK_OP(>, _GT, val1, val2)\
' /opt/colmap/src/colmap/util/logging.h && \

    # CRITICAL FIX 6/6 (Prediction Macro): Replace the usage with the built-in function.
    # We must run this as a final step because of the way the previous sed replacement works.
    sed -i 's/GOOGLE_PREDICT_BRANCH_NOT_TAKEN(x)/(__builtin_expect(!(x), 0))/g' /opt/colmap/src/colmap/util/logging.h && \
    
    cmake -S /opt/colmap -B /opt/colmap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF \
      -DGUI_ENABLED=OFF \
      -DBUILD_SHARED_LIBS=ON \
      -DCGAL_ENABLED=ON && \
    cmake --build /opt/colmap/build && \
    cmake --install /opt/colmap/build && \
    find /opt/colmap/build -name 'libPoseLib.so' -exec cp {} /usr/local/lib/ \; && \
    rm -rf /opt/colmap

# ---------------------------------------------------------------------
# ---------------------------------------------------------------------

# --- 5) Build and Install GLOMAP 1.1.0 ---
# This is the original Step 4.
ENV CMAKE_BUILD_PARALLEL_LEVEL=1

RUN git clone --depth 1 https://github.com/colmap/glomap.git /opt/glomap && \
    cmake -S /opt/glomap -B /opt/glomap/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF && \
    cmake --build /opt/glomap/build && \
    cmake --install /opt/glomap/build && \
    rm -rf /opt/glomap

# ---------------------------------------------------------------------

# --- 6) Configure Runtime Linker (CRITICAL FIX) ---
# This is the original Step 5. Remove the obsolete symlink command.
RUN echo "/usr/local/lib" >> /etc/ld.so.conf.d/colmap.conf && ldconfig


# --- 7) Final Execution Setup ---
COPY ./src /src
WORKDIR /src
RUN chmod +x ./action
ENTRYPOINT ["./action"]