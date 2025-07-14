#!/bin/bash


# QSMxT SLURM Job Script
# 
# This script runs QSMxT (Quantitative Susceptibility Mapping) processing
# on a SLURM cluster for a single subject/session.
#
# Usage: sbatch qsmxt_slurm_n.sh <INPUT_DIR> <SUBJECT> <SESSION> <OUTPUT_DIR>
#
# Arguments:
#   INPUT_DIR  - Path to input BIDS directory containing raw data
#   SUBJECT    - Subject identifier (e.g., sub-001)
#   SESSION    - Session identifier (e.g., ses-01)
#   OUTPUT_DIR - Path to output directory for processed results
#
# The script processes GRE data using QSMxT with the following features:
#   - QSM reconstruction using PDF background field removal
#   - SWI processing
#
# Output is initially placed in a supplementary directory. Upon successful completion, 
# the directory containing the final results is moved to the specified output 
# location.



#SBATCH -c 32	
#SBATCH --mem 120G	
#SBATCH --time 120	
#SBATCH -o /data/u_kuegler_software/git/qsm/run_qsmxt/logs/%j.out	# redirect the output
#

INPUT_DIR="$1"
SUBJECT="$2"
SESSION="$3"
OUTPUT_DIR="$4"
echo "Input Directory: ${INPUT_DIR}"
echo "Subject/Session: ${SUBJECT}/${SESSION}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "--------"

SUPPL_DIR=${OUTPUT_DIR}/Supplementary/${SUBJECT}/${SESSION}
mkdir -p ${SUPPL_DIR}

cd ${SUPPL_DIR}

source ~/bash.singularity
source ~/bash.conda
conda activate qsmxt8

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

    # --do_segmentation \
    # --use_existing_masks \
    # --existing_masks_pipeline 'synthstrip' \

if [ $? -eq 0 ]; then
    mv "${SUPPL_DIR}/${SUBJECT}/${SESSION}" "${OUTPUT_DIR}/${SUBJECT}/${SESSION}"
fi