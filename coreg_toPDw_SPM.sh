#!/bin/bash

#
# Coregister Chimaps to PDw Space using SPM
#
# This script submits SLURM jobs to coregister T1w and MTw Chimap files to PDw Chimap
# reference space using SPM12 rigid body transformation.
#
# Usage: ./coreg_toPDw_SPM.sh <INPUT_DIR>
#
# Arguments:
#   INPUT_DIR - Path to directory containing Chimap files in transform_to_orig subdirectories
#
# Directory structure:
#   INPUT_DIR: sub-XXX/ses-XX/anat/transform_to_orig/*_MPM_Chimap.nii
#
# The script will:
#   1. Find all subjects and sessions in the input directory
#   2. For each subject/session, identify T1w, MTw, and PDw Chimaps in transform_to_orig/
#   3. Submit SLURM jobs to coregister T1w and MTw Chimaps to PDw Chimap
#   4. Output files will be saved in coreg_toPDw/ subdirectory with _desc-coregToPDw suffix
#
# Output naming:
#   Input:  sub-XXX_ses-XX_acq-T1w_MPM_Chimap.nii
#   Output: sub-XXX_ses-XX_acq-T1w_desc-coregToPDw_MPM_Chimap.nii
#

# Check arguments
if [ $# -ne 1 ]; then
    echo "Error: Incorrect number of arguments"
    echo "Usage: $0 <INPUT_DIR>"
    echo ""
    echo "Arguments:"
    echo "  INPUT_DIR - Path to directory with Chimaps (sub-XXX/ses-XX/anat/transform_to_orig/)"
    echo ""
    echo "Example: $0 /path/to/qsmxt_output"
    exit 1
fi

INPUT_DIR="$1"

# Validate directory
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist."
    exit 1
fi

# SLURM script and partitions
SLURM_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/coreg_toPDw_slurm.sh"
SLURM_PARTITIONS="short,group_servers,gr_weiskopf"

if [ ! -f "$SLURM_SCRIPT" ]; then
    echo "Error: SLURM script not found: $SLURM_SCRIPT"
    exit 1
fi

echo "============================================="
echo "Coregister Chimaps to PDw Space (SPM)"
echo "============================================="
echo "Input Directory: $INPUT_DIR"
echo "SLURM Script: $SLURM_SCRIPT"
echo "============================================="

# Counter for statistics
total_subjects=0
total_sessions=0
total_jobs=0
total_skipped=0

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
        
        # transform_to_orig directory containing Chimaps
        transform_to_orig_dir="${session_dir}/anat/transform_to_orig"
        
        if [ ! -d "$transform_to_orig_dir" ]; then
            echo "    Warning: transform_to_orig directory not found: $transform_to_orig_dir"
            continue
        fi
        
        # Create output directory for coregistered files
        coreg_dir="${session_dir}/anat/coreg_toPDw"
        mkdir -p "$coreg_dir"
        
        # Find PDw Chimap (reference)
        pdw_chimap=$(find "${transform_to_orig_dir}" -maxdepth 1 -type f \( -name "${subj}*acq-PDw*MPM_Chimap.nii" -o -name "${subj}*acq-PDw*MPM_Chimap.nii.gz" \) | head -n 1)
        
        if [ -z "$pdw_chimap" ]; then
            echo "    Warning: PDw Chimap not found in $transform_to_orig_dir"
            continue
        fi
        
        echo "    PDw reference: $(basename $pdw_chimap)"
        
        # Process T1w and MTw Chimaps
        for acq_type in T1w MTw; do
            # Find the Chimap for this acquisition type
            moving_chimap=$(find "${transform_to_orig_dir}" -maxdepth 1 -type f \( -name "${subj}*acq-${acq_type}*MPM_Chimap.nii" -o -name "${subj}*acq-${acq_type}*MPM_Chimap.nii.gz" \) | head -n 1)
            
            if [ -z "$moving_chimap" ]; then
                echo "    Warning: ${acq_type} Chimap not found, skipping"
                ((total_skipped++))
                continue
            fi
            
            echo "    Submitting ${acq_type} coregistration job:"
            echo "      Moving:    $(basename $moving_chimap)"
            echo "      Reference: $(basename $pdw_chimap)"
            echo "      Output dir: $coreg_dir"
            
            # Submit SLURM job
            job_id=$(sbatch -p ${SLURM_PARTITIONS} --parsable "$SLURM_SCRIPT" "$moving_chimap" "$pdw_chimap" "$coreg_dir")
            
            if [ $? -eq 0 ]; then
                echo "      Job submitted: $job_id"
                ((total_jobs++))
            else
                echo "      Error: Failed to submit job for ${acq_type}"
            fi
        done
        
    done
done

echo ""
echo "============================================="
echo "Job Submission Summary"
echo "============================================="
echo "Total subjects processed: $total_subjects"
echo "Total sessions processed: $total_sessions"
echo "Total jobs submitted: $total_jobs"
echo "Total skipped: $total_skipped"
echo "============================================="

if [ $total_jobs -eq 0 ]; then
    echo "Warning: No jobs were submitted"
    exit 1
fi
