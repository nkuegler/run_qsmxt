#!/bin/bash

#
# QSMxT Batch Job Submission Script (Deprecated)
#
# AUTHOR:
#   Niklas Kuegler (kuegler@cbs.mpg.de)
#   Max Planck Institute for Human Cognitive and Brain Sciences (MPI CBS), Leipzig
#
# LICENSE: MIT
# SOURCE:  https://github.com/nkuegler/run_qsmxt
#
# DEPENDENCIES:
#   - SLURM workload manager
#
# Example usage:
# ./call_qsmxt.sh sub-001 sub-002 sub-003
# ./call_qsmxt.sh sub-006 sub-017 sub-021 sub-027 sub-031 sub-042 sub-048 sub-051 sub-057 sub-061 sub-062 sub-109

# Print project banner
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../print_banner.sh"

SLURM_PARTITIONS="short,group_servers,gr_weiskopf"
SLURM_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/qsmxt_slurm.sh"

# Loop over all subject names passed as arguments
prev_jobid=""
for subj in "$@"; do
    if [ -z "$prev_jobid" ]; then
        jobid=$(sbatch -p ${SLURM_PARTITIONS} ${SLURM_SCRIPT} "$subj" | awk '{print $4}')
        echo "Submitted batch job $jobid for $subj"
    else
        jobid=$(sbatch --dependency=afterany:$prev_jobid -p ${SLURM_PARTITIONS} ${SLURM_SCRIPT} "$subj" | awk '{print $4}')
        echo "Submitted batch job $jobid for $subj with dependency on job $prev_jobid"
    fi
    prev_jobid=$jobid
done



