################################################################################
FROM nvcr.io/nvidia/cuda:11.8.0-base-ubuntu22.04 as base
################################################################################

# Install necessary dependencies for PETSc and CUDA development packages
COPY setup.packages.sh /setup.packages.sh
COPY devel.packages.txt /devel.packages.txt
RUN /setup.packages.sh /devel.packages.txt

# Set environment variables for open-mpi to run as root 
# (used for the make check command)
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# Set environment variables for PETSc
ENV PETSC_DIR=/opt/petsc
ENV PETSC_ARCH=arch-cuda

# Clone PETSc source code
RUN git clone -b v3.19.3 https://gitlab.com/petsc/petsc.git $PETSC_DIR

# Configure and build PETSc
WORKDIR $PETSC_DIR
RUN ./configure PETSC_ARCH=$PETSC_ARCH --with-cuda=1
RUN make PETSC_DIR=$PETSC_DIR PETSC_ARCH=$PETSC_ARCH all