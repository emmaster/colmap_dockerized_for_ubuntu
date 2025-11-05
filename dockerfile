
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
    
    # CRITICAL FIX 1/5 (Cleanup): Remove all conflicting and old fixes
    sed -i '/#include <glog\/logging.h>/d' /opt/colmap/src/colmap/util/logging.h && \
    sed -i '/#include <glog\/raw_logging.h>/d' /opt/colmap/src/colmap/util/logging.h && \
    sed -i '/#define _EQ __COUNTER__/d' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 2/5 (Header Conflict Fix): Block MiniGlog header
    # Targets the main MiniGlog header file (logging.h) to prevent redefinition errors.
    sed -i 's/\#include <glog\/log_severity.h>/ /g' /usr/local/include/ceres/internal/miniglog/glog/logging.h && \
    
    # CRITICAL FIX 3/5 (Header/Type/VLOG_IS_ON Fix): 
    # Inserts necessary standard glog headers, type aliases, and a simple VLOG_IS_ON macro.
    # FIX: Re-introduce a simplified VLOG_IS_ON macro that should be compatible.
    printf '#include <stdint.h>\n#include <glog/logging.h>\n#include <glog/raw_logging.h>\n\nnamespace google { using int32 = int32_t; using int64 = int64_t; }\n\n#ifndef VLOG_IS_ON\n#define VLOG_IS_ON(verboselevel) (verboselevel <= google::COUNTER_TO_VLOG_IS_ON_VARIABLE)\n#endif\n' > /tmp/colmap_glog_fixes && \
    sed -i '38 r /tmp/colmap_glog_fixes' /opt/colmap/src/colmap/util/logging.h && \
    rm /tmp/colmap_glog_fixes && \
    
    # CRITICAL FIX 4/5 (Macro Definitions - RAW_CHECK(condition, message) Fix)
    # Fix 4a: Replace '::google::LogMessageFatal' with global 'LogMessageFatal'
    sed -i 's/::google::LogMessageFatal/LogMessageFatal/g' /opt/colmap/src/colmap/util/logging.h && \
    
    # Fix 4b: Insert Operator Counters
    sed -i '87i#define _EQ __COUNTER__\n#define _NE __COUNTER__\n#define _LE __COUNTER__\n#define _LT __COUNTER__\n#define _GE __COUNTER__\n#define _GT __COUNTER__' /opt/colmap/src/colmap/util/logging.h && \
    
    # Fix 4c (THROW_CHECK Fix): Redefine THROW_CHECK_OP for correct expansion.
    # Also include the definition for the missing __CheckOptionOpImpl function.
    # FIX: Definition for missing __CheckOptionOpImpl
    printf '#define THROW_CHECK_OP(op, name, val1, val2) \\\n  RAW_CHECK((val1) op (val2), "") \n\n#define THROW_CHECK(condition) \\\n  LOG_IF(FATAL, (__builtin_expect(!(condition), 0))) << "Check failed: " #condition << ": "\n\n#define THROW_CHECK_EQ(val1, val2) THROW_CHECK_OP(==, _EQ, val1, val2)\n#define THROW_CHECK_NE(val1, val2) THROW_CHECK_OP(!=, _NE, val1, val2)\n#define THROW_CHECK_LE(val1, val2) THROW_CHECK_OP(<=, _LE, val1, val2)\n#define THROW_CHECK_LT(val1, val2) THROW_CHECK_OP(<, _LT, val1, val2)\n#define THROW_CHECK_GE(val1, val2) THROW_CHECK_OP(>=, _GE, val1, val2)\n#define THROW_CHECK_GT(val1, val2) THROW_CHECK_OP(>, _GT, val1, val2)\n\n#define THROW_CHECK_NOTNULL(ptr) \\\n  (ptr == NULL ? colmap::LogMessageFatal(__FILE__, __LINE__).stream() << "Check failed: " #ptr << " is NULL" : (ptr))\n\n#define THROW_CHECK_NOTNULL_T(ptr, exception) \\\n  (ptr == NULL ? colmap::LogMessageFatalThrow<exception>(__FILE__, __LINE__).stream() << "Check failed: " #ptr << " is NULL" : (ptr))' > /tmp/colmap_throw_checks && \
    sed -i '94,103d' /opt/colmap/src/colmap/util/logging.h && \
    sed -i '93 r /tmp/colmap_throw_checks' /opt/colmap/src/colmap/util/logging.h && \
    rm /tmp/colmap_throw_checks && \
    
    # CRITICAL FIX 5/5 (LogMessageFatalThrow type definition)
    # Defines the LogMessageFatalThrow template struct.
    sed -i '92i\template <typename E>\nstruct LogMessageFatalThrow : public google::LogMessageFatal {\n  LogMessageFatalThrow(const char* file, int line) : LogMessageFatal(file, line) {}\n  ~LogMessageFatalThrow() noexcept(false) {\n    throw E(this->str());\n  }\n};\n' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 6/6 (Define missing option check function)
    # FIX: Define the missing __CheckOptionOpImpl function required by CHECK_OPTION macros.
    sed -i 's/namespace colmap {/namespace colmap {\n\ntemplate <typename T, typename U>\ninline bool __CheckOptionOpImpl(const char* file, int line, const char* op_str, const T& v1, const char* expr1, const U& v2, const char* expr2) {\n  return google::CheckOpHelper<T, U>(v1, expr1, v2, expr2, op_str).error_for_program_failure().IsOK();\n}\n/g' /opt/colmap/src/colmap/util/logging.h && \
    
    # CRITICAL FIX 7/7 (Clean up VLOG_IS_ON Call Site Fix)
    # The VLOG_IS_ON macro is now defined in logging.h (Fix 3/5), so we must undo Fix 6/6.
    # FIX: Restore VLOG_IS_ON(N) calls in bundle_adjustment.cc
    sed -i 's/google::GetVLogCommandLine() >= 1/VLOG_IS_ON(1)/g' /opt/colmap/src/colmap/estimators/bundle_adjustment.cc && \
    sed -i 's/google::GetVLogCommandLine() >= 2/VLOG_IS_ON(2)/g' /opt/colmap/src/colmap/estimators/bundle_adjustment.cc && \
    sed -i 's/google::GetVLogCommandLine() >= 3/VLOG_IS_ON(3)/g' /opt/colmap/src/colmap/estimators/bundle_adjustment.cc && \
    
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