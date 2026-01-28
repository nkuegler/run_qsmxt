#!/bin/bash

#
# Transform Chimap Data to MPM Space
#
# This script transforms T1w and MTw Chimap files to match the space of co-registered
# MPM reference files using FSL's flirt with sform-based transformation.
#
# Background:
#   The reference files (T1w and MTw in REF_DIR) are the original acquisitions that
#   have been co-registered to the PDw acquisition space using SPM rigid transformation.
#   This script transforms the corresponding Chimaps (from QSMxT processing) to match
#   the same co-registered space.
#
# Usage: ./transform_to_mpm.sh <INPUT_DIR> <REF_DIR>
#
# Arguments:
#   INPUT_DIR - Path to directory containing Chimap files to transform
#   REF_DIR   - Path to directory containing co-registered MPM reference files 
#
# Directory structures:
#   INPUT_DIR:  sub-XXX/ses-XX/anat/transform_to_orig/*_MPM_Chimap.nii or *.nii.gz
#               (QSMxT Chimap outputs transformed back to original space)
#   REF_DIR:    sub-XXX/ses-XX/anat/Supplementary/MPMCalc/*acq-{T1w,MTw}*coregistered*.nii
#               (Original acquisitions co-registered to PDw space via SPM)
#
# The script will:
#   1. Find all subjects and sessions in the input directory
#   2. For each subject/session, create a transform_to_mpm subdirectory
#   3. Transform T1w and MTw Chimap files to match their corresponding co-registered references
#   4. Use acquisition-specific references (T1w Chimap → T1w coregistered reference, etc.)
#

# Check arguments
if [ $# -ne 2 ]; then
    echo "Error: Incorrect number of arguments"
    echo "Usage: $0 <INPUT_DIR> <REF_DIR>"
    echo ""
    echo "Arguments:"
    echo "  INPUT_DIR - Path to files to transform (sub-XXX/ses-XX/anat/*.nii)"
    echo "  REF_DIR   - Path to MPM reference files"
    echo ""
    echo "Example: $0 /path/to/qsmxt_output /path/to/mpm_output"
    exit 1
fi

INPUT_DIR="$1"
REF_DIR="$2"

# Validate directories
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist."
    exit 1
fi

if [ ! -d "$REF_DIR" ]; then
    echo "Error: Reference directory '$REF_DIR' does not exist."
    exit 1
fi

# FSL version
FSL_VERSION="6.0.6"

echo "============================================="
echo "Transform Chimap Data to MPM Space"
echo "============================================="
echo "Input Directory: $INPUT_DIR (QSMxT Chimaps)"
echo "Reference Directory: $REF_DIR (Co-registered acquisitions)"
echo "FSL Version: $FSL_VERSION"
echo ""
echo "Transformation strategy:"
echo "  - T1w Chimaps → T1w co-registered reference"
echo "  - MTw Chimaps → MTw co-registered reference"
echo "  (References are original acquisitions co-registered to PDw space via SPM)"
echo "============================================="

# Counter for statistics
total_subjects=0
total_sessions=0
total_files=0
total_transformed=0
total_skipped=0
total_errors=0

# Find all subject directories in input
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
        
        # Anatomical directory with transform_to_orig subdirectory
        anat_dir="${session_dir}/anat"
        transform_to_orig_dir="${anat_dir}/transform_to_orig"
        
        if [ ! -d "$transform_to_orig_dir" ]; then
            echo "    Warning: transform_to_orig directory not found: $transform_to_orig_dir"
            continue
        fi
        
        # Create transformation output directory
        transform_to_mpm_dir="${anat_dir}/transform_to_mpm"
        mkdir -p "$transform_to_mpm_dir"
        
        # Corresponding reference directory
        ref_mpm_dir="${REF_DIR}/${subj}/${session}/anat/Supplementary/MPMCalc"
        
        if [ ! -d "$ref_mpm_dir" ]; then
            echo "    Warning: Reference MPM directory not found: $ref_mpm_dir"
            continue
        fi
        
        # Process all T1w and MTw .nii and .nii.gz files
        while IFS= read -r -d '' input_file; do
            ((total_files++))
            filename=$(basename "$input_file")
            
            # Check if file is T1w or MTw
            if [[ "$filename" != *"acq-T1w"* ]] && [[ "$filename" != *"acq-MTw"* ]]; then
                echo "    Skipping $filename (not T1w or MTw)"
                ((total_skipped++))
                continue
            fi
            
            # Determine acquisition type and corresponding reference
            if [[ "$filename" == *"acq-T1w"* ]]; then
                acq_type="T1w"
            elif [[ "$filename" == *"acq-MTw"* ]]; then
                acq_type="MTw"
            fi
            
            # Find the acquisition-specific reference file (PDw MPM_{T1w,MTw})
            ref_file=$(find "${ref_mpm_dir}" -type f \( -name "${subj}*acq-PDw*_echo-01*part-mag*MPM_${acq_type}.nii" -o -name "${subj}*acq-PDw*_echo-01*part-mag*MPM_${acq_type}.nii.gz" \) | head -n 1)
            
            if [ -z "$ref_file" ]; then
                echo "    Warning: Could not find PDw MPM_${acq_type} reference file for $filename"
                ((total_errors++))
                continue
            fi
            
            echo "    Transforming $filename → $(basename $ref_file)"
            
            # Run FSL flirt transformation
            SCWRAP fsl $FSL_VERSION flirt \
                -in "$input_file" \
                -ref "$ref_file" \
                -out "${transform_to_mpm_dir}/${filename}" \
                -interp spline \
                -applyxfm \
                -usesqform 2>&1 | grep -v "^$"
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                echo "      Success: ${transform_to_mpm_dir}/${filename}"
                ((total_transformed++))
            else
                echo "      Error: Failed to transform $filename"
                ((total_errors++))
            fi
            
        done < <(find "${transform_to_orig_dir}" -maxdepth 1 -type f \( -name "*MPM_Chimap.nii" -o -name "*MPM_Chimap.nii.gz" \) -print0)
        
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
