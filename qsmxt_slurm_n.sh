#!/bin/bash


# QSMxT SLURM Job Script
# 
# This script runs QSMxT (Quantitative Susceptibility Mapping) processing
# on a SLURM cluster for a single subject/session.
#
# Usage: sbatch qsmxt_slurm_n.sh <INPUT_DIR> <OUTPUT_DIR> <SUBJECT> [SESSION] [TRANSF_TO_ORIG]
#
# Arguments:
#   INPUT_DIR      - Path to input BIDS directory containing raw data
#   OUTPUT_DIR     - Path to output directory for processed results
#   SUBJECT        - Subject identifier (e.g., sub-001)
#   SESSION        - (Optional) Session identifier (e.g., ses-01)
#   TRANSF_TO_ORIG - (Optional) Set to 'true' to transform outputs back to original space
#
# The script processes GRE data using QSMxT with the following features:
#   - QSM reconstruction using PDF background field removal
#   - SWI processing
#
# Output is initially placed in a supplementary directory. Upon successful completion, 
# the directory containing the final results is moved to the specified output 
# location.
#
# If TRANSF_TO_ORIG is set to 'true', all output .nii/.nii.gz files will be
# transformed back to their corresponding original input space using FSL's flirt.



#SBATCH -c 60	
#SBATCH --mem 200G	
#SBATCH --time 180	
#SBATCH -o /data/u_kuegler_software/git/qsm/run_qsmxt/logs/%j_qsmxt.out	# redirect the output
#

FSL_VERSION="6.0.6"

INPUT_DIR="$1"
OUTPUT_DIR="$2"
SUBJECT="$3"
SESSION="$4"  # Optional - may be empty
TRANSF_TO_ORIG="${5:-false}"  # Optional - defaults to false

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
echo "Transform to original space: ${TRANSF_TO_ORIG}"
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
        --do_r2starmap \
        --do_template \
        --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' \
        --subjects "${SUBJECT}" \
        --sessions "${SESSION}" \
        --recs rec-loraksRsos \
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
        --do_r2starmap \
        --do_template \
        --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' \
        --subjects "${SUBJECT}" \
        --recs rec-loraksRsos \
        --acqs acq-T1w acq-PDw acq-MTw \
        --bf_algorithm 'pdf' \
        --use_existing_masks \
        --existing_masks_pipeline 'synthstrip' \
        --qsm_reference none \
        --auto_yes
fi

    # --do_segmentation \ # requires fastsurfer for segmentation
    # --use_existing_masks \
    # --existing_masks_pipeline 'synthstrip' \
    # --gpu 'cuda'

if [ $? -eq 0 ]; then
    # Transform outputs back to original space if requested
    if [ "$TRANSF_TO_ORIG" = "true" ]; then
        echo "--------"
        echo "Transforming outputs back to original space..."
        echo "--------"
        
        # Determine directories
        if [[ -n "$SESSION" ]]; then
            PROCESSED_ANAT_DIR="${SUPPL_DIR}/${SUBJECT}/${SESSION}/anat"
            INPUT_SUBJ_DIR="${INPUT_DIR}/${SUBJECT}/${SESSION}/anat"
            TRANSF_OUTPUT_DIR="${SUPPL_DIR}/${SUBJECT}/${SESSION}/transf_to_orig"
        else
            PROCESSED_ANAT_DIR="${SUPPL_DIR}/${SUBJECT}/anat"
            INPUT_SUBJ_DIR="${INPUT_DIR}/${SUBJECT}/anat"
            TRANSF_OUTPUT_DIR="${SUPPL_DIR}/${SUBJECT}/transf_to_orig"
        fi
        
        # Create transformation output directory
        mkdir -p "${TRANSF_OUTPUT_DIR}"
        
        # Find all .nii and .nii.gz files in processed directory
        while IFS= read -r -d '' output_file; do
            filename=$(basename "$output_file")
            
            # Determine acquisition type
            acq_type=""
            if [[ "$filename" == *"acq-PDw"* ]]; then
                acq_type="PDw"
            elif [[ "$filename" == *"acq-MTw"* ]]; then
                acq_type="MTw"
            elif [[ "$filename" == *"acq-T1w"* ]]; then
                acq_type="T1w"
            else
                echo "  Skipping $filename (no recognized acquisition type)"
                continue
            fi
            
            # Find corresponding original file in input directory
            # Pattern: sub-*_acq-{acq_type}*echo-01*part-phase*MPM.nii
            original_file=$(find "${INPUT_SUBJ_DIR}" -type f -name "${SUBJECT}*acq-${acq_type}*echo-01*part-phase*MPM.nii" | head -n 1)
            
            if [ -z "$original_file" ]; then
                echo "  Warning: Could not find original ${acq_type} file for $filename"
                continue
            fi
            
            echo "  Transforming $filename using reference: $(basename $original_file)"
            
            # Run FSL flirt transformation
            SCWRAP fsl $FSL_VERSION flirt \
                -in "$output_file" \
                -ref "$original_file" \
                -out "${TRANSF_OUTPUT_DIR}/${filename}" \
                -interp spline \
                -applyxfm \
                -usesqform
            
            if [ $? -eq 0 ]; then
                echo "    Success: Created ${TRANSF_OUTPUT_DIR}/${filename}"
            else
                echo "    Error: Failed to transform $filename"
            fi
            
        done < <(find "${PROCESSED_ANAT_DIR}" -type f \( -name "*.nii" -o -name "*.nii.gz" \) -print0)
        
        echo "--------"
        echo "Transformation to original space completed"
        echo "--------"
    fi
    
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

