#!/bin/bash

#
# Transform Processed Outputs to Original Space
#
# This script transforms already processed QSMxT outputs back to their original
# input space using FSL's flirt with sform-based transformation.
#
# Usage: ./transform_to_orig.sh <INPUT_DIR> <REF_DIR>
#
# Arguments:
#   INPUT_DIR - Path to directory containing files to transform (sub-XXX/ses-XX/anat/*.nii)
#   REF_DIR  - Path to directory containing reference files (same structure)
#
# The script will:
#   1. Find all subjects and sessions in the output directory
#   2. For each subject/session, create a transform_to_orig subdirectory
#   3. Transform all .nii and .nii.gz files to match their corresponding input space
#   4. Use acquisition type (PDw, MTw, T1w) to match output to input reference files
#

# Check arguments
if [ $# -ne 2 ]; then
    echo "Error: Incorrect number of arguments"
    echo "Usage: $0 <INPUT_DIR> <REF_DIR>"
    echo ""
    echo "Arguments:"
    echo "  INPUT_DIR - Path to processed outputs (sub-XXX/ses-XX/anat/*.nii)"
    echo "  REF_DIR  - Path to original inputs (same structure)"
    echo ""
    echo "Example: $0 /path/to/qsmxt_output /path/to/original_input"
    exit 1
fi

INPUT_DIR="$1"
REF_DIR="$2"

# Validate directories
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Output directory '$INPUT_DIR' does not exist."
    exit 1
fi

if [ ! -d "$REF_DIR" ]; then
    echo "Error: Input directory '$REF_DIR' does not exist."
    exit 1
fi

# FSL version
FSL_VERSION="6.0.6"

echo "============================================="
echo "Transform Processed Outputs to Original Space"
echo "============================================="
echo "Output Directory: $INPUT_DIR"
echo "Input Directory: $REF_DIR"
echo "FSL Version: $FSL_VERSION"
echo "============================================="

# Counter for statistics
total_subjects=0
total_sessions=0
total_files=0
total_transformed=0
total_skipped=0
total_errors=0

# Find all subject directories in output
for subj_dir in "${INPUT_DIR}"/sub-*; do
    if [ ! -d "$subj_dir" ]; then
        continue
    fi
    
    subj=$(basename "$subj_dir")
    ((total_subjects++))
    
    echo ""
    echo "Processing subject: $subj"
    
    # Find all session directories for this subject
    for session_dir in "${subj_dir}"/ses-*; do
        if [ ! -d "$session_dir" ]; then
            continue
        fi
        
        session=$(basename "$session_dir")
        ((total_sessions++))
        
        echo "  Processing session: $session"
        
        # Anatomical directory
        anat_dir="${session_dir}/anat"
        
        if [ ! -d "$anat_dir" ]; then
            echo "    Warning: Anatomical directory not found: $anat_dir"
            continue
        fi
        
        # Create transformation output directory
        transform_dir="${anat_dir}/transform_to_orig"
        mkdir -p "$transform_dir"
        
        # Corresponding input directory
        input_anat_dir="${REF_DIR}/${subj}/${session}/anat"
        
        if [ ! -d "$input_anat_dir" ]; then
            echo "    Warning: Input directory not found: $input_anat_dir"
            continue
        fi
        
        # Process all .nii and .nii.gz files
        while IFS= read -r -d '' output_file; do
            ((total_files++))
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
                echo "    Skipping $filename (no recognized acquisition type)"
                ((total_skipped++))
                continue
            fi
            
            # Find corresponding original file
            original_file=$(find "${input_anat_dir}" -type f -name "${subj}*acq-${acq_type}*echo-01*part-phase*MPM.nii" | head -n 1)
            
            if [ -z "$original_file" ]; then
                echo "    Warning: Could not find original ${acq_type} file for $filename"
                ((total_skipped++))
                continue
            fi
            
            echo "    Transforming $filename using reference: $(basename $original_file)"
            
            # Run FSL flirt transformation
            SCWRAP fsl $FSL_VERSION flirt \
                -in "$output_file" \
                -ref "$original_file" \
                -out "${transform_dir}/${filename}" \
                -interp spline \
                -applyxfm \
                -usesqform 2>&1 | grep -v "^$"
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                # Unzip the output file if it was created as .nii.gz
                if [ -f "${transform_dir}/${filename}.gz" ]; then
                    gunzip -f "${transform_dir}/${filename}.gz"
                    echo "      Success (unzipped): ${transform_dir}/${filename}"
                else
                    echo "      Success: ${transform_dir}/${filename}"
                fi
                ((total_transformed++))
            else
                echo "      Error: Failed to transform $filename"
                ((total_errors++))
            fi
            
        # done < <(find "${anat_dir}" -type f \( -name "*.nii" -o -name "*.nii.gz" \) -print0)
        done < <(find "${anat_dir}" -type f \( -name "*MPM_Chimap.nii" \) -print0)

    done
done

echo ""
echo "============================================="
echo "Transformation Summary"
echo "============================================="
echo "Total subjects processed: $total_subjects"
echo "Total sessions processed: $total_sessions"
echo "Total files found: $total_files"
echo "Successfully transformed: $total_transformed"
echo "Skipped: $total_skipped"
echo "Errors: $total_errors"
echo "============================================="

if [ $total_errors -gt 0 ]; then
    exit 1
fi
