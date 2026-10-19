#!/bin/bash
#SBATCH --job-name=columbus
#SBATCH --output=columbus722.%j.out
#SBATCH --ntasks=1
#SBATCH --mail-type=ALL
#SBATCH --mail-user=your.email@richmond.edu
#SBATCH --partition=parish
#SBATCH --mem=720G
#SBATCH --cpus-per-task=20

# SLURM Columbus script with Parallel CI
# Instructions:
# Parallel CI must be set up in colinp CI input as well as job control.
# Edit SBATCH variables. For a single node, only edit mail-type, mail-user, mem, and cpus-per-task
# Edit the 2 memory variables below, TOTAL_MEM and MEM_PER_PROC
# Columbus will run in a localscratch directory.
# You can ssh to the node it is running on and examine it while it runs.
# runls and columbus722.{job number}.out are updated in the submission directory as it runs
# (i.e. readable from the head node).
# Submit using "sbatch <this file name>" from within your columbus job directory.

TOTAL_MEM=720000      # Total memory in MB (equal to SBATCH --mem)
MEM_PER_PROC=36000    # Memory per process in MB (number given by colinp + some padding)

date
echo "========================================="
echo "NODES:         $SLURM_NODELIST"
echo "JOB_ID:        $SLURM_JOB_ID"
echo "NCPU:          $SLURM_CPUS_PER_TASK"
echo "TOTAL MEM:     $TOTAL_MEM MB"
echo "MEM PER PROC:  $MEM_PER_PROC MB"
echo "========================================="

cd $SLURM_SUBMIT_DIR

# Create localscratch
LOCALSCRATCH="/localscratch/${USER}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
mkdir -p $LOCALSCRATCH

# Remove old work files
rm -rf GEOMS COSMO LISTINGS RESTART MOCOEFS MOLDEN WORK GRADIENTS runls runc.error

# Copy the working directory to localscratch. Exclude files that will be overwritten.
rsync -a \
      --exclude='columbus722.*.*' \
      --exclude='.*' \
      $SLURM_SUBMIT_DIR/* $LOCALSCRATCH/
cd $LOCALSCRATCH

# Load modules
module load columbus/722

# Global array environment variable overrides
export GA_MEMORY_LIMIT="${TOTAL_MEM}000"
export ARMCI_DEFAULT_SHMMAX=8192
export MXSEG=1000

# Memory options for runc
RUNCOPTS="-msmp $TOTAL_MEM -m $MEM_PER_PROC"

# cleanup trap, runs on both normal and abnormal exit
cleanup() {
    local exit_status=$?
    echo "COLUMBUS EXIT AT `date` with status $exit_status"

    # remove large files before copying results back
    # if [ $exit_status -eq 0 ]; then
    #     echo "Job succeeded"
    #     rm -rf WORK
    # else
    #     # keep existing behavior: only drop the huge files
    #     local rmfiles=$(find WORK -size +50M)
    #     [ -n "$rmfiles" ] && rm -f $rmfiles
    # fi


    # Copy back results
    echo "Copying back results from $LOCALSCRATCH to $SLURM_SUBMIT_DIR"
    rsync -a --exclude='columbus722.*.*' --exclude='.*' $LOCALSCRATCH/* $SLURM_SUBMIT_DIR/

    # Copy runls and runc.error to save basic output files associated with this job
    cp "$SLURM_SUBMIT_DIR/runls" "$SLURM_SUBMIT_DIR/runls.$SLURM_JOB_ID"
    cp "$SLURM_SUBMIT_DIR/runc.error" "$SLURM_SUBMIT_DIR/runc.error.$SLURM_JOB_ID"

    # Clean up localscratch
    echo "Cleaning up $LOCALSCRATCH"
    rm -fr $LOCALSCRATCH

    date
    exit $exit_status # Actual program exit
}
trap cleanup EXIT

# Run Columbus with full path
echo "COLUMBUS START AT `date`"
/usr/bin/time -v $COLUMBUS/runc $RUNCOPTS -nproc $SLURM_CPUS_PER_TASK > $SLURM_SUBMIT_DIR/runls
# Not the end of the script, the cleanup() trap will now run.
