#!/bin/bash -e
#SBATCH --job-name=columbus72_test
#SBATCH --output=columbus722_test.%j.out
#SBATCH --ntasks=1
#SBATCH --mail-type=ALL
#SBATCH --mail-user=kritim.rijal@richmond.edu
#SBATCH --partition=basic
#SBATCH --mem=12G
#SBATCH --cpus-per-task=1

date
echo "I ran on:"
echo "SLURM_NODELIST=$SLURM_NODELIST"

# Change to the directory containing Columbus input files
cd $SLURM_SUBMIT_DIR/

# Load modules
#export COLUMBUS=/usr/local/sw/Columbus/columbus-v7.2.2/Columbus
module load columbus/722

# Run Columbus with full path
/usr/bin/time -v $COLUMBUS/runc -m 12000 > runls

date
