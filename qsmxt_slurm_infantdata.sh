#!/bin/bash


# QSMxT SLURM Job Script
# 
# This script runs QSMxT (Quantitative Susceptibility Mapping) processing
# on a SLURM cluster for a single subject/session.
#
# Usage: sbatch qsmxt_slurm_infantdata.sh <INPUT_DIR> <OUTPUT_DIR> <SUBJECT> [SESSION] [TRANSF_TO_ORIG]
#
# Arguments:
#   INPUT_DIR      - Path to input BIDS directory containing raw data
#   OUTPUT_DIR     - Path to output directory for processed results
#   SUBJECT        - Subject identifier (e.g., sub-001)
#   SESSION        - (Optional) Session identifier (e.g., ses-01)
#   TRANSF_TO_ORIG - (Optional) NOT IMPLEMENTED YET - placeholder for future functionality
#
# The script processes GRE data using QSMxT with the following features:
#   - QSM reconstruction using PDF background field removal
#   - SWI processing
#
# Output is initially placed in a supplementary directory. Upon successful completion, 
# the directory containing the final results is moved to the specified output 
# location.
#
# NOTE: The TRANSF_TO_ORIG flag is accepted but not functional in this script yet.



#SBATCH -c 60	
#SBATCH --mem 200G	
#SBATCH --time 180	
#SBATCH -o /data/u_kuegler_software/git/qsm/run_qsmxt/logs/%j_qsmxt.out	# redirect the output
#

INPUT_DIR="$1"
OUTPUT_DIR="$2"
SUBJECT="$3"
SESSION="$4"  # Optional - may be empty
TRANSF_TO_ORIG="${5:-false}"  # Optional - defaults to false (NOT IMPLEMENTED)

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
if [ "$TRANSF_TO_ORIG" = "true" ]; then
    echo "Transform to original space: ${TRANSF_TO_ORIG} (NOT IMPLEMENTED)"
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
        --runs run-01 \
        --recs rec-loraks \
        --acqs acq-T1w acq-PDw acq-MTw \
        --bf_algorithm 'pdf' \
        --use_existing_masks \
        --existing_masks_pipeline 'synthstrip' \
        --qsm_reference none \
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
        --runs run-01 \
        --recs rec-loraks \
        --acqs acq-T1w acq-PDw acq-MTw \
        --bf_algorithm 'pdf' \
        --use_existing_masks \
        --existing_masks_pipeline 'synthstrip' \
        --qsm_reference none \
        --auto_yes
fi

## originally used command (without custom brain masks)
# qsmxt /data/p_03037/LORAKS_adults/bids/derivatives/LORAKS_LCPCA /data/p_03037/LORAKS_adults/bids/derivatives/qsm/qsmxt_pdf_manTest/ --premade 'gre' --do_qsm --do_swi --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' --subjects sub-001 --sessions ses-01 --runs run-01 --recs rec-loraks --acqs acq-T1w acq-PDw acq-MTw --bf_algorithm 'pdf' --auto_yes

    # --do_segmentation \ # requires fastsurfer for segmentation
    # --use_existing_masks \
    # --existing_masks_pipeline 'synthstrip' \
    # --gpu 'cuda'

if [ $? -eq 0 ]; then
    mkdir -p "${OUTPUT_DIR}"
    
    if [[ -n "$SESSION" ]]; then
        # Session specified - check and warn if it already exists
        if [[ -d "${OUTPUT_DIR}/${SUBJECT}/${SESSION}" ]]; then
            echo "--------"
            echo "WARNING: Session ${SESSION} already exists in output directory for ${SUBJECT}"
            echo "WARNING: Existing files will be overwritten!"
            echo "--------"
        fi
    else
        # No session specified - check and warn if subject already exists
        if [[ -d "${OUTPUT_DIR}/${SUBJECT}" ]]; then
            echo "--------"
            echo "WARNING: Subject ${SUBJECT} already exists in output directory"
            echo "WARNING: Existing files will be overwritten!"
            echo "--------"
        fi
    fi
    
    # Use cp to merge with existing subject directory
    cp -r "${SUPPL_DIR}/${SUBJECT}" "${OUTPUT_DIR}/"

    # Only remove from supplementary if copy succeeded
    if [ $? -eq 0 ]; then
        rm -rf "${SUPPL_DIR}/${SUBJECT}"
        echo "Successfully moved data to ${OUTPUT_DIR}"
    else
        echo "ERROR: Failed to copy results to output directory"
        echo "Data remains in supplementary directory: ${SUPPL_DIR}/${SUBJECT}"
        exit 1
    fi
fi
        

