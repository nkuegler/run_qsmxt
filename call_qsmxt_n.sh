#!/bin/bash

#
# QSMxT Batch Job Submission Script
#
# This script submits QSMxT processing jobs to SLURM for multiple subjects.
# It automatically discovers sessions with anatomical data and submits jobs
# with dependencies to ensure sequential processing.
#
# Usage: ./call_qsmxt_n.sh [--seq] [--transform-to-orig] [--sub <SUBJECT[,SUBJECT,...]>] [--ses <SESSION[,SESSION,...]>] <INPUT_DIR> <OUTPUT_DIR>
#
# Options:
#   --seq            - Process jobs sequentially (with dependencies). Default is parallel.
#   --transform-to-orig - Transform outputs back to original input space using FSL flirt
#   --sub <SUBJECT[,SUBJECT,...]> - Process only the specified subject(s) (e.g., sub-001 or sub-001,sub-002)
#                     If not specified, all sub-* directories in INPUT_DIR will be processed.
#   --ses <SESSION[,SESSION,...]> - Process only the specified session(s) for all subjects (e.g., ses-01 or ses-01,ses-02)
#
# Arguments:
#   INPUT_DIR  - Path to input BIDS directory containing subject data
#   OUTPUT_DIR - Path to output directory for processed results
#
# The script will:
#   1. Check each subject directory for session subdirectories
#   2. Verify that sessions contain 'anat' directories with .nii or .nii.gz files
#   3. Submit SLURM jobs for valid subject/session combinations
#   4. By default, submit all jobs in parallel for maximum throughput
#   5. With --seq flag, chain jobs with dependencies for sequential processing
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

# Print project banner
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/print_banner.sh"

# Function to check if a session directory is valid (contains anatomical data)
# Arguments:
#   $1 - Session directory path
# Returns:
#   0 if valid, 1 if invalid
is_valid_session() {
    local session_dir="$1"
    local anat_dir="${session_dir}/anat"
    
    if [ -d "$anat_dir" ] && [ -n "$(find "$anat_dir" -name "*.nii" -o -name "*.nii.gz" 2>/dev/null)" ]; then
        return 0
    fi
    return 1
}

# Function to submit a SLURM job for a subject/session combination
# Arguments:
#   $1 - Subject ID
#   $2 - Session ID (can be empty string for no session)
#   $3 - Session directory path (for validation, can be empty)
# Global variables used:
#   INPUT_DIR, OUTPUT_DIR, SEQUENTIAL, TRANSFORM_TO_ORIG
#   SLURM_PARTITIONS, SLURM_SCRIPT
#   prev_jobid, total_jobs (modified)
submit_job() {
    local subj="$1"
    local session="$2"
    local session_dir="$3"
    local jobid=""
    
    # Validate session if session_dir is provided
    if [ -n "$session_dir" ]; then
        if ! is_valid_session "$session_dir"; then
            echo "  Skipping session: $session (no anat directory with .nii or .nii.gz files found)"
            return 1
        fi
    fi
    
    # Determine session label for output
    local session_label=""
    if [ -n "$session" ]; then
        session_label="${subj}/${session}"
    else
        session_label="${subj} (no session)"
    fi
    
    # Submit SLURM job
    if [ "$SEQUENTIAL" = true ]; then
        # Sequential processing: add dependency on previous job
        if [ -z "$prev_jobid" ]; then
            jobid=$(sbatch -p ${SLURM_PARTITIONS} -x "drachenkopf" ${SLURM_SCRIPT} "$INPUT_DIR" "$OUTPUT_DIR" "$subj" "$session" "$TRANSFORM_TO_ORIG" | awk '{print $4}')
            echo "  Submitted batch job $jobid for ${session_label}"
        else
            jobid=$(sbatch --dependency=afterany:$prev_jobid -p ${SLURM_PARTITIONS} -x "drachenkopf" ${SLURM_SCRIPT} "$INPUT_DIR" "$OUTPUT_DIR" "$subj" "$session" "$TRANSFORM_TO_ORIG" | awk '{print $4}')
            echo "  Submitted batch job $jobid for ${session_label} with dependency on job $prev_jobid"
        fi
        prev_jobid=$jobid
    else
        # Parallel processing: submit job without dependencies
        jobid=$(sbatch -p ${SLURM_PARTITIONS} -x "drachenkopf" ${SLURM_SCRIPT} "$INPUT_DIR" "$OUTPUT_DIR" "$subj" "$session" "$TRANSFORM_TO_ORIG" | awk '{print $4}')
        echo "  Submitted batch job $jobid for ${session_label}"
    fi
    ((total_jobs++))
    return 0
}

# Check if sufficient arguments are provided and parse options
SEQUENTIAL=false
TRANSFORM_TO_ORIG=false
SESSION_TO_PROCESS=""
SUBJECTS_TO_PROCESS=""

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --seq)
            SEQUENTIAL=true
            shift
            ;;
        --transform-to-orig)
            TRANSFORM_TO_ORIG=true
            shift
            ;;
        --sub)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --sub flag requires a subject identifier argument"
                exit 1
            fi
            SUBJECTS_TO_PROCESS="$2"
            shift 2
            ;;
        --ses)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --ses flag requires a session identifier argument"
                exit 1
            fi
            SESSION_TO_PROCESS="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Usage: $0 [--seq] [--transform-to-orig] [--sub <SUBJECT[,SUBJECT,...]>] [--ses <SESSION[,SESSION,...]>] <INPUT_DIR> <OUTPUT_DIR>"
            echo "Options:"
            echo "  --seq            Process jobs sequentially (default is parallel)"
            echo "  --transform-to-orig Transform outputs back to original input space"
            echo "  --sub <SUBJECT[,SUBJECT,...]> Process only the specified subject(s)"
            echo "  --ses <SESSION[,SESSION,...]> Process only the specified session(s) for all subjects"

            exit 1
            ;;
        *)
            break # Exit loop when we hit non-option arguments
            ;;
    esac
done

# Check if sufficient arguments remain after option parsing
if [ $# -lt 2 ]; then
    echo "Error: Insufficient arguments provided."
    echo "Usage: $0 [--seq] [--transform-to-orig] [--sub <SUBJECT[,SUBJECT,...]>] [--ses <SESSION[,SESSION,...]>] <INPUT_DIR> <OUTPUT_DIR>"
    echo "Options:"
    echo "  --seq            Process jobs sequentially (default is parallel)"
    echo "  --transform-to-orig Transform outputs back to original input space"
    echo "  --sub <SUBJECT[,SUBJECT,...]> Process only the specified subject(s)"
    echo "  --ses <SESSION[,SESSION,...]> Process only the specified session(s) for all subjects"
    echo "Example: $0 /path/to/input /path/to/output"
    echo "Example: $0 --sub sub-001,sub-002 /path/to/input /path/to/output"
    echo "Example: $0 --seq --ses ses-01 /path/to/input /path/to/output"

    echo "Example: $0 --sub sub-001,sub-002 --ses ses-01,ses-02 /path/to/input /path/to/output"
    echo "Example: $0 --transform-to-orig --ses ses-01 /path/to/input /path/to/output"
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
SLURM_PARTITIONS="standard,group_servers,gr_weiskopf"
SLURM_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/qsmxt_slurm_n.sh"
# SLURM_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/qsmxt_slurm_infantdata.sh"

echo "Input Directory: $INPUT_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Processing Mode: $([ "$SEQUENTIAL" = true ] && echo "Sequential" || echo "Parallel")"
echo "Transform to original space: $TRANSFORM_TO_ORIG"
if [ -n "$SESSION_TO_PROCESS" ]; then
    echo "Session to process: $SESSION_TO_PROCESS"
else
    echo "Session to process: All sessions"
fi
echo ""

# Build list of subjects to process
subjects_to_process=()
if [ -n "$SUBJECTS_TO_PROCESS" ]; then
    # Parse comma-separated subject list
    IFS=',' read -ra SUBJECT_ARRAY <<< "$SUBJECTS_TO_PROCESS"
    for subj in "${SUBJECT_ARRAY[@]}"; do
        subjects_to_process+=("$subj")
    done
else
    # Discover all sub-* directories in INPUT_DIR
    while IFS= read -r -d '' subj_dir; do
        if [ -d "$subj_dir" ]; then
            subj=$(basename "$subj_dir")
            subjects_to_process+=("$subj")
        fi
    done < <(find "${INPUT_DIR}" -maxdepth 1 -name "sub-*" -type d -print0 2>/dev/null)
fi

echo "Subjects to process: ${subjects_to_process[*]}"

# Check if any subjects were found
if [ ${#subjects_to_process[@]} -eq 0 ]; then
    echo "Error: No subjects found to process."
    echo "  - If using --sub, check that the specified subjects exist in $INPUT_DIR"
    echo "  - If not using --sub, check that there are sub-* directories in $INPUT_DIR"
    exit 1
fi

echo "============================================="

# Initialize job tracking
prev_jobid=""
total_jobs=0

# Loop over all subjects to process
for subj in "${subjects_to_process[@]}"; do
    subj_dir="${INPUT_DIR}/${subj}"
    
    # Check if subject directory exists
    if [ ! -d "$subj_dir" ]; then
        echo "Warning: Subject directory '$subj_dir' not found. Skipping $subj."
        continue
    fi
    
    echo "Processing subject: $subj"
    
    # Build list of sessions to process
    sessions_to_process=()
    sessions_found=false
    
    if [ -n "$SESSION_TO_PROCESS" ]; then
        # Parse comma-separated session list
        IFS=',' read -ra SESSION_ARRAY <<< "$SESSION_TO_PROCESS"
        for session in "${SESSION_ARRAY[@]}"; do
            session_dir="${subj_dir}/${session}"
            if [ -d "$session_dir" ]; then
                sessions_to_process+=("$session")
            else
                echo "  Warning: Session $session not found for subject $subj"
            fi
        done
    else
        # Discover all sessions
        while IFS= read -r -d '' session_dir; do
            if [ -d "$session_dir" ]; then
                session=$(basename "$session_dir")
                sessions_to_process+=("$session")
            fi
        done < <(find "${subj_dir}" -maxdepth 1 -name "ses-*" -type d -print0 2>/dev/null)
    fi
    
    # Process each session in the list
    for session in "${sessions_to_process[@]}"; do
        session_dir="${subj_dir}/${session}"
        if is_valid_session "$session_dir"; then
            sessions_found=true
            echo "  Found valid session: $session"
            submit_job "$subj" "$session" "$session_dir"
        fi
    done
    
    # If no session directories found (or no valid sessions), check for anat directory directly in subject directory
    if [ "$sessions_found" = false ]; then
        if is_valid_session "$subj_dir"; then
            sessions_found=true
            echo "  Found anatomical data directly in subject directory (no session directories)"
            submit_job "$subj" "" ""
        fi
    fi
    
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