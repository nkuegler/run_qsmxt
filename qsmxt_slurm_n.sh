#!/bin/bash


# QSMxT SLURM Job Script
# 
# This script runs QSMxT (Quantitative Susceptibility Mapping) processing
# on a SLURM cluster for a single subject/session.
#
# Usage: sbatch qsmxt_slurm_n.sh <INPUT_DIR> <OUTPUT_DIR> <SUBJECT> [SESSION]
#
# Arguments:
#   INPUT_DIR  - Path to input BIDS directory containing raw data
#   OUTPUT_DIR - Path to output directory for processed results
#   SUBJECT    - Subject identifier (e.g., sub-001)
#   SESSION    - (Optional) Session identifier (e.g., ses-01)
#
# The script processes GRE data using QSMxT with the following features:
#   - QSM reconstruction using PDF background field removal
#   - SWI processing
#
# Output is initially placed in a supplementary directory. Upon successful completion, 
# the directory containing the final results is moved to the specified output 
# location.



#SBATCH -c 60	
#SBATCH --mem 120G	
#SBATCH --time 180	
#SBATCH -o /data/u_kuegler_software/git/qsm/run_qsmxt/logs/%j.out	# redirect the output
#

INPUT_DIR="$1"
OUTPUT_DIR="$2"
SUBJECT="$3"
SESSION="$4"  # Optional - may be empty

echo "Input Directory: ${INPUT_DIR}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "Subject: ${SUBJECT}"
if [[ -n "$SESSION" ]]; then
    echo "Session: ${SESSION}"
    SUPPL_DIR=${OUTPUT_DIR}/Supplementary/${SUBJECT}/${SESSION}
else
    echo "Session: Not specified"
    SUPPL_DIR=${OUTPUT_DIR}/Supplementary/${SUBJECT}
fi
echo "--------"

mkdir -p ${SUPPL_DIR}

cd ${SUPPL_DIR}

source ~/bash.singularity
source ~/bash.conda
conda activate qsmxt8

# Build qsmxt command with conditional session argument
if [[ -n "$SESSION" ]]; then
    # Session specified - include both --subjects and --sessions
    qsmxt ${INPUT_DIR} \
        ${SUPPL_DIR} \
        --premade 'gre' \
        --do_qsm \
        --do_swi \
        --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' \
        --subjects "${SUBJECT}" \
        --sessions "${SESSION}" \
        --recs rec-loraksRsos \
        --acqs acq-T1w acq-PDw acq-MTw \
        --bf_algorithm 'pdf' \
        --auto_yes
else
    # No session specified - include only --subjects, process all sessions
    qsmxt ${INPUT_DIR} \
        ${SUPPL_DIR} \
        --premade 'gre' \
        --do_qsm \
        --do_swi \
        --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' \
        --subjects "${SUBJECT}" \
        --recs rec-loraksRsos \
        --acqs acq-T1w acq-PDw acq-MTw \
        --bf_algorithm 'pdf' \
        --auto_yes
fi

    # --do_segmentation \
    # --use_existing_masks \
    # --existing_masks_pipeline 'synthstrip' \

if [ $? -eq 0 ]; then
    mkdir -p "${OUTPUT_DIR}"
    mv "${SUPPL_DIR}/${SUBJECT}" "${OUTPUT_DIR}"
fi
