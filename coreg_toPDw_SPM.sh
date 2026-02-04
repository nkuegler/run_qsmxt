#!/bin/bash

#
# Coregister and Average Chimaps to PDw Space using SPM and FSL
#
# This script submits SLURM jobs to coregister T1w and MTw Chimap files to PDw Chimap
# reference space using SPM12 rigid body transformation, then automatically averages all
# three Chimaps (PDw reference + coregistered T1w + coregistered MTw) using FSL.
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
#   4. Submit a dependent averaging job that merges and averages the three Chimaps
#   5. Output files will be saved in coreg_toPDw/ subdirectory
#
# Output files:
#   Coregistered: coreg_sub-XXX_ses-XX_acq-T1w_rec-loraksRsos_MPM_Chimap.nii
#                 coreg_sub-XXX_ses-XX_acq-MTw_rec-loraksRsos_MPM_Chimap.nii
#   Averaged:     sub-XXX_ses-XX_averaged_Chimap.nii
#   Mean:         sub-XXX_ses-XX_mean_Chimap.nii
#
# Job dependencies:
#   The averaging job runs only after both coregistration jobs complete successfully.
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
AVG_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/average_chimaps_slurm.sh"
SLURM_PARTITIONS="short,group_servers,gr_weiskopf"

if [ ! -f "$SLURM_SCRIPT" ]; then
    echo "Error: SLURM script not found: $SLURM_SCRIPT"
    exit 1
fi

if [ ! -f "$AVG_SCRIPT" ]; then
    echo "Error: Averaging script not found: $AVG_SCRIPT"
    exit 1
fi

echo "============================================="
echo "Coregister Chimaps to PDw Space (SPM) and Average them using FSL"
echo "============================================="
echo "Input Directory: $INPUT_DIR"
echo "SLURM Script: $SLURM_SCRIPT"
echo "============================================="

# Counter for statistics
total_subjects=0
total_sessions=0
total_jobs=0
total_skipped=0
total_avg_jobs=0

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
        
        # Initialize job tracking for this session
        t1w_job_id=""
        mtw_job_id=""
        t1w_coreg_file=""
        mtw_coreg_file=""
        
        # Process T1w and MTw Chimaps
        for acq_type in T1w MTw; do
            # Find the Chimap for this acquisition type
            moving_chimap=$(find "${transform_to_orig_dir}" -maxdepth 1 -type f \( -name "${subj}*acq-${acq_type}*MPM_Chimap.nii" -o -name "${subj}*acq-${acq_type}*MPM_Chimap.nii.gz" \) | head -n 1)
            
            if [ -z "$moving_chimap" ]; then
                echo "    Warning: ${acq_type} Chimap not found, skipping"
                ((total_skipped++))
                continue
            fi
            
            # Determine expected output filename (coreg_ prefix)
            moving_basename=$(basename "$moving_chimap")
            expected_coreg_file="${coreg_dir}/coreg_${moving_basename}"
            
            echo "    Submitting ${acq_type} coregistration job:"
            echo "      Moving:    $(basename $moving_chimap)"
            echo "      Reference: $(basename $pdw_chimap)"
            echo "      Output dir: $coreg_dir"
            
            # Submit SLURM job
            job_id=$(sbatch -p ${SLURM_PARTITIONS} --parsable "$SLURM_SCRIPT" "$moving_chimap" "$pdw_chimap" "$coreg_dir")
            
            if [ $? -eq 0 ]; then
                echo "      Job submitted: $job_id"
                ((total_jobs++))
                
                # Store job ID and expected output file
                if [ "$acq_type" = "T1w" ]; then
                    t1w_job_id="$job_id"
                    t1w_coreg_file="$expected_coreg_file"
                elif [ "$acq_type" = "MTw" ]; then
                    mtw_job_id="$job_id"
                    mtw_coreg_file="$expected_coreg_file"
                fi
            else
                echo "      Error: Failed to submit job for ${acq_type}"
            fi
        done
        
        # Submit averaging job if both coregistration jobs were successfully submitted
        if [ -n "$t1w_job_id" ] && [ -n "$mtw_job_id" ]; then
            echo "    Submitting averaging job (depends on ${t1w_job_id} and ${mtw_job_id}):"
            echo "      PDw Reference: $(basename $pdw_chimap)"
            echo "      T1w coreg: $(basename $t1w_coreg_file)"
            echo "      MTw coreg: $(basename $mtw_coreg_file)"
            
            # Submit averaging job with dependency on both coregistration jobs
            avg_job_id=$(sbatch -p ${SLURM_PARTITIONS} --parsable \
                --dependency=afterok:${t1w_job_id}:${mtw_job_id} \
                "$AVG_SCRIPT" "$pdw_chimap" "$t1w_coreg_file" "$mtw_coreg_file" "$coreg_dir")
            
            if [ $? -eq 0 ]; then
                echo "      Averaging job submitted: $avg_job_id"
                ((total_avg_jobs++))
            else
                echo "      Error: Failed to submit averaging job"
            fi
        else
            echo "    Skipping averaging job (not all coregistration jobs were submitted)"
        fi
        
    done
done

echo ""
echo "============================================="
echo "Job Submission Summary"
echo "============================================="
echo "Total subjects processed: $total_subjects"
echo "Total sessions processed: $total_sessions"
echo "Total coregistration jobs submitted: $total_jobs"
echo "Total averaging jobs submitted: $total_avg_jobs"
echo "Total skipped: $total_skipped"
echo "============================================="

if [ $total_jobs -eq 0 ]; then
    echo "Warning: No jobs were submitted"
    exit 1
fi
