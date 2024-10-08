# Introduction 
Docker container that builds PETSc with CUDA support. 

# Requirements
As a prerequisite, [install NVIDIA docker](https://github.com/NVIDIA/nvidia-docker)

This container is based on `nvcr.io/nvidia/cuda:11.8.0-base-ubuntu22.04`, verify the cuda container installation by running the `nvidia-smi` command to poll for the installed GPUs:
```
$ sudo docker run --gpus all --rm nvcr.io/nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

# Build and Test
```
$ sudo docker build --progress=plain -t petsc-cuda .
```

Enable the `--progress=plain` option to show the output of the build commands. When the build finishes you should see the following:

```
...
=========================================
Now to check if the libraries are working do:
make PETSC_DIR=/opt/petsc PETSC_ARCH=arch-cuda check
=========================================
```

# Verify
```
$ sudo docker run --gpus all --rm petsc-cuda make check
```

Should run show the following output:
```
Running check examples to verify correct installation
Using PETSC_DIR=/opt/petsc and PETSC_ARCH=arch-cuda
C/C++ example src/snes/tutorials/ex19 run successfully with 1 MPI process
C/C++ example src/snes/tutorials/ex19 run successfully with 2 MPI processes
C/C++ example src/snes/tutorials/ex19 run successfully with cuda
Completed test examples
```

# References
[PETSc installation tutorial](https://petsc.org/release/install/install_tutorial/)

[CUDA configuration](https://petsc.org/release/install/install/#cuda)

The `setup.packages.sh` script to install dependencies is taken from here: <https://github.com/tensorflow/tensorflow/blob/master/tensorflow/tools/tf_sig_build_dockerfiles/setup.packages.sh>
