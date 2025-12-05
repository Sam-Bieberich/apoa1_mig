#!/usr/bin/bash

# Check number of arguments
if [ "$#" -ne "2" ] ; then
    echo "This script requires two arguments:"
    echo "  NAMD input file"
    echo "  NAMD output file"
    exit -1
fi

# Check SLURM node/task layout
if [ "$SLURM_NNODES" -ne "$SLURM_NTASKS" ] ; then
    echo "The number of tasks per node is NOT 1! Please use the same number in -n x -N x in your job submission."
    exit -1
fi

# CPU core affinity
pemap="1-71"
commap="0"
ppn=71

# Launch NAMD
srun --mpi=pmi2 $TACC_NAMD_GPU_BIN/namd3 \
    +ppn $ppn \
    +pemap $pemap \
    +commap $commap \
    +devices 0 \
    "$1" &> "$2"