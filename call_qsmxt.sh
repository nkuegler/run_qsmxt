#!/bin/bash

### before running this script, make sure to make singularity containers available and to set the following conda environment
## sing # alias to make singularity containers available
## conda activate qsmxt8


# Example usage:
# ./call_qsmxt.sh sub-001 sub-002 sub-003
# ./call_qsmxt.sh sub-006 sub-017 sub-021 sub-027 sub-031 sub-042 sub-048 sub-051 sub-057 sub-061 sub-062 sub-109


# Loop over all subject names passed as arguments
for subj in "$@"; do
    sbatch -p short,group_servers,gr_weiskopf /data/u_kuegler_software/git/qsm/run_qsmxt/qsmxt_slurm.sh "$subj"
done

