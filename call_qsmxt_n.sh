#!/bin/bash

#
# QSMxT Batch Job Submission Script
#
# This script submits QSMxT processing jobs to SLURM for multiple subjects.
# It automatically discovers sessions with anatomical data and submits jobs
# with dependencies to ensure sequential processing.
#
# Usage: ./call_qsmxt_n.sh [--seq] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> <SUBJECT2> ...
#
# Options:
#   --seq      - Process jobs sequentially (with dependencies). Default is parallel.
#
# Arguments:
#   INPUT_DIR  - Path to input BIDS directory containing subject data
#   OUTPUT_DIR - Path to output directory for processed results  
#   SUBJECT*   - One or more subject identifiers (e.g., sub-001, sub-002)
#
# The script will:
#   1. Check each subject directory for session subdirectories
#   2. Verify that sessions contain 'anat' directories with .nii or .nii.gz files
#   3. Submit SLURM jobs for valid subject/session combinations
#   4. By default, submit all jobs in parallel for maximum throughput
#   5. With --seq flag, chain jobs with dependencies for sequential processing
#

# Check if sufficient arguments are provided and parse options
SEQUENTIAL=false

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --seq)
            SEQUENTIAL=true
            shift
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Usage: $0 [--seq] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ..."
            echo "Options:"
            echo "  --seq    Process jobs sequentially (default is parallel)"
            exit 1
            ;;
        *)
            break # Exit loop when we hit non-option arguments
            ;;
    esac
done

# Check if sufficient arguments remain after option parsing
if [ $# -lt 3 ]; then
    echo "Error: Insufficient arguments provided."
    echo "Usage: $0 [--seq] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ..."
    echo "Options:"
    echo "  --seq    Process jobs sequentially (default is parallel)"
    echo "Example: $0 /path/to/input /path/to/output sub-001 sub-002 sub-003"
    echo "Example: $0 --seq /path/to/input /path/to/output sub-001 sub-002 sub-003"
    exit 1
fi

# Parse command line arguments
INPUT_DIR="$1"
OUTPUT_DIR="$2"
shift 2

# Validate input directory
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist."
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# SLURM configuration
SLURM_PARTITIONS="short,group_servers,gr_weiskopf"
SLURM_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/qsmxt_slurm_n.sh"

echo "Input Directory: $INPUT_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Processing Mode: $([ "$SEQUENTIAL" = true ] && echo "Sequential" || echo "Parallel")"
echo "Subjects to process: $@"
echo "============================================="

# Initialize job tracking
prev_jobid=""
total_jobs=0

# Loop over all subject names passed as arguments
for subj in "$@"; do
    subj_dir="${INPUT_DIR}/${subj}"
    
    # Check if subject directory exists
    if [ ! -d "$subj_dir" ]; then
        echo "Warning: Subject directory '$subj_dir' not found. Skipping $subj."
        continue
    fi
    
    echo "Processing subject: $subj"
    
    # Find all session directories for this subject
    sessions_found=false
    
    # Use find to robustly locate session directories
    while IFS= read -r -d '' session_dir; do
        if [ -d "$session_dir" ]; then
            session=$(basename "$session_dir")
            anat_dir="${session_dir}/anat"
            
            # Check if anat directory exists and contains .nii or .nii.gz files
            if [ -d "$anat_dir" ] && [ -n "$(find "$anat_dir" -name "*.nii" -o -name "*.nii.gz" 2>/dev/null)" ]; then
                sessions_found=true
                echo "  Found valid session: $session"
                
                # Submit SLURM job for this subject/session combination
                if [ "$SEQUENTIAL" = true ]; then
                    # Sequential processing: add dependency on previous job
                    if [ -z "$prev_jobid" ]; then
                        jobid=$(sbatch -p ${SLURM_PARTITIONS} -x "drachenkopf" ${SLURM_SCRIPT} "$INPUT_DIR" "$subj" "$session" "$OUTPUT_DIR" | awk '{print $4}')
                        echo "  Submitted batch job $jobid for ${subj}/${session}"
                    else
                        jobid=$(sbatch --dependency=afterany:$prev_jobid -p ${SLURM_PARTITIONS} -x "drachenkopf" ${SLURM_SCRIPT} "$INPUT_DIR" "$subj" "$session" "$OUTPUT_DIR" | awk '{print $4}')
                        echo "  Submitted batch job $jobid for ${subj}/${session} with dependency on job $prev_jobid"
                    fi
                    prev_jobid=$jobid
                else
                    # Parallel processing: submit job without dependencies
                    jobid=$(sbatch -p ${SLURM_PARTITIONS} -x "drachenkopf" ${SLURM_SCRIPT} "$INPUT_DIR" "$subj" "$session" "$OUTPUT_DIR" | awk '{print $4}')
                    echo "  Submitted batch job $jobid for ${subj}/${session}"
                fi
                ((total_jobs++))
            else
                echo "  Skipping session: $session (no anat directory with .nii or .nii.gz files found)"
            fi
        fi
    done < <(find "${subj_dir}" -maxdepth 1 -name "ses-*" -type d -print0 2>/dev/null)
    
    if [ "$sessions_found" = false ]; then
        echo "  Warning: No valid sessions found for subject $subj"
    fi
    
    echo ""
done

echo "============================================="
echo "Total jobs submitted: $total_jobs"
echo "Processing mode: $([ "$SEQUENTIAL" = true ] && echo "Sequential (jobs will run one after another)" || echo "Parallel (jobs will run simultaneously)")"
if [ $total_jobs -gt 0 ]; then
    if [ "$SEQUENTIAL" = true ]; then
        echo "Last job ID: $prev_jobid"
    fi
    echo "Monitor progress with: squeue -u \$USER"
fi



