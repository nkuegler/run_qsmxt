#!/bin/bash

# before running this script, make sure to make singularity containers available and to set the following conda environment
# sing
# conda activate qsmxt8


# Example usage:
# ./call_qsmxt.sh sub-001 sub-002 sub-003


cd /data/p_03037/LORAKS/bids/derivatives/qsm

# Loop over all subject names passed as arguments
for subj in "$@"; do
    sbatch -p short,group_servers,gr_weiskopf /data/p_03037/LORAKS/bids/derivatives/qsm/code/qsmxt_slurm.sh "$subj"
done

