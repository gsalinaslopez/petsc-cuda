################################################################################
FROM nvcr.io/nvidia/cuda:11.8.0-base-ubuntu22.04 as base
################################################################################

ARG UCX_BRANCH="v1.14.1"
ARG OMPI_BRANCH="v4.1.5"
ARG OPENFOAM_VERSION="v2112"
ARG SCOTCH_VER="7.0.3"
ARG PETSC_VER="3.19.3"
ARG USE_HYPRE=TRUE

COPY setup.packages.sh /setup.packages.sh
COPY devel.packages.txt /devel.packages.txt
RUN /setup.packages.sh /devel.packages.txt

ENV UCX_HOME=/opt/ucx \
    OMPI_HOME=/opt/ompi \
    CUDA_HOME=/usr/local/cuda

WORKDIR /tmp

# Install UCX
# https://openucx.readthedocs.io/en/master/running.html#openmpi-with-ucx
RUN cd /tmp/ \
    && git clone https://github.com/openucx/ucx.git -b ${UCX_BRANCH} \
    && cd ucx \
    && ./autogen.sh \
    && mkdir build \
    && cd build \
    && ../contrib/configure-release --prefix=$UCX_HOME \
        --with-cuda=$CUDA_HOME \
        --enable-optimizations  \
        --disable-logging \
        --disable-debug \
        --disable-examples \
    && make -j $(nproc)  \
    && make install

# Install OpenMPI
# https://docs.open-mpi.org/en/v5.0.0rc7/networking/cuda.html#how-do-i-build-open-mpi-with-cuda-aware-support
RUN cd /tmp \
    && git clone --recursive https://github.com/open-mpi/ompi.git -b ${OMPI_BRANCH} \
    && cd ompi \
    && ./autogen.pl \
    && mkdir build \
    && cd build \
    && ../configure --prefix=$OMPI_HOME --with-ucx=$UCX_HOME \
        --enable-mca-no-build=btl-uct  \
        --with-cuda=$CUDA_HOME \
        --enable-mpi \
        --enable-mpi-fortran=yes \
        --disable-man-pages \
        --disable-debug \
    && make -j $(nproc) \
    && make install

# Adding OpenMPI and UCX to Environment
ENV PATH=$OMPI_HOME/bin:$UCX_HOME/bin:$PATH \
    PKG_CONFIG_PATH=$OMPI_HOME/lib/pkgconfig:$UCX_HOME/lib/pkgconfig:$PKG_CONFIG_PATH

# Used to suppres `UCX  WARN  unused environment variable: UCX_HOME` warning
ENV UCX_WARN_UNUSED_ENV_VARS=n

# Set environment variables for open-mpi to run as root
# (used for the make check command)
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# Install PETSc and OpenFOAM
ENV OPENFOAM_DIR=/home/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} \
    THIRDPARTY_DIR=/home/OpenFOAM/ThirdParty-${OPENFOAM_VERSION} \
    WM_NCOMPPROCS=$(nproc)

SHELL ["/bin/bash", "-c"]

WORKDIR /home/OpenFOAM/

RUN git clone -b OpenFOAM-${OPENFOAM_VERSION} https://develop.openfoam.com/Development/openfoam.git OpenFOAM-${OPENFOAM_VERSION}
RUN git clone -b ${OPENFOAM_VERSION} https://develop.openfoam.com/Development/ThirdParty-common.git ThirdParty-${OPENFOAM_VERSION}

# Modified makePETSc script that builds it with CUDA support
COPY makePETSC /home/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}/makePETSC
RUN chmod 777 /home/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}/makePETSC

# Clone and build SCOTCH
RUN source ${OPENFOAM_DIR}/etc/bashrc \
    && cd ThirdParty-${OPENFOAM_VERSION} \
    && git checkout v2212 etc/makeFiles/scotch/Makefile.inc.Linux.shlib \
    && git clone -b v${SCOTCH_VER} https://gitlab.inria.fr/scotch/scotch.git scotch_${SCOTCH_VER} \
    && sed -i -e "s|.*SCOTCH_VERSION=scotch_.*|SCOTCH_VERSION=scotch_${SCOTCH_VER}|g" ${OPENFOAM_DIR}/etc/config.sh/scotch \
    && ./Allwmake -q

# Clone and build PETSc with the makePETSC script
RUN source ${OPENFOAM_DIR}/etc/bashrc \
    && cd ThirdParty-${OPENFOAM_VERSION} \
    && git clone -b v${PETSC_VER} https://gitlab.com/petsc/petsc.git petsc-${PETSC_VER} \
    && sed -i -e "s|petsc_version=petsc-.*|petsc_version=petsc-${PETSC_VER}|g" ${OPENFOAM_DIR}/etc/config.sh/petsc \
    && if [[ ${USE_HYPRE} ]] ; then \
        ./makePETSC; \
    else \
        ./makePETSC -no-hypre; \
    fi

RUN source ${OPENFOAM_DIR}/etc/bashrc \
    && echo ${WM_PROJECT_DIR} \
    && cd ${OPENFOAM_DIR} \
    && ./Allwmake -q -l

ENV PATH=${OPENFOAM_DIR}/bin:${OPENFOAM_DIR}/platforms/linux64GccDPInt32Opt/bin:$PATH \
    LD_LIBRARY_PATH=${OPENFOAM_DIR}/platforms/linux64GccDPInt32Opt/lib:$LD_LIBRARY_PATH \
    LIBRARY_PATH=${OPENFOAM_DIR}/platforms/linux64GccDPInt32Opt/lib:$LIBRARY_PATH 

# Build external solver petsc4Foam
RUN source ${OPENFOAM_DIR}/etc/bashrc \
    && cd ${OPENFOAM_DIR} \
    && git submodule update --init ${OPENFOAM_DIR}/modules/external-solver \
    && cd ${OPENFOAM_DIR}/modules/external-solver \
    && ./Allwmake -j -q -l \
    && mkdir /openfoam/ \
    && cp -r $(dirname $(find /root/ -iname libpetscFoam.so)) /openfoam

ENV PATH=${THIRDPARTY_DIR}/petsc-${PETSC_VER}/DPInt32/bin:${THIRDPARTY_DIR}/scotch_${SCOTCH_VER}/bin:$PATH \
    LD_LIBRARY_PATH=/openfoam/lib:${THIRDPARTY_DIR}/petsc-${PETSC_VER}/lib:${THIRDPARTY_DIR}/petsc-${PETSC_VER}/DPInt32/lib:${THIRDPARTY_DIR}/platforms/linux64GccDPInt32/lib:${THIRDPARTY_DIR}/platforms/linux64GccDPInt32/petsc-${PETSC_VER}/lib:$LD_LIBRARY_PATH \
    LIBRARY_PATH=/openfoam/lib:${THIRDPARTY_DIR}/petsc-${PETSC_VER}/lib:${THIRDPARTY_DIR}/petsc-${PETSC_VER}/DPInt32/lib:${THIRDPARTY_DIR}/platforms/linux64GccDPInt32/lib:${THIRDPARTY_DIR}/platforms/linux64GccDPInt32/petsc-${PETSC_VER}/lib:$LIBRARY_PATH

# Setting up OpenFOAM HPC Benchmark suite
# https://develop.openfoam.com/committees/hpc/-/wikis/home
COPY /benchmark /benchmark

WORKDIR /benchmark

RUN chmod -R 777 /benchmark/*.sh \
    && ./load_benchmark.sh --prefix /benchmark

CMD ["/bin/bash"]
