#!/bin/bash

#
# SynthStrip Batch Job Submission Script
#
# This script submits brain extraction jobs using mri_synthstrip to SLURM for multiple subjects.
# It automatically discovers sessions with anatomical data and submits jobs
# for brain mask creation.
#
# Usage: ./call_synthstrip.sh [--acqs <ACQ_TYPES>] [--no-csf] [--holefill <ITERATIONS>] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> <SUBJECT2> ...
#
# Options:
#   --acqs <ACQ_TYPES>      - Comma-separated acquisition types (default: PDw,T1w,MTw)
#   --no-csf                - Exclude CSF from brain mask
#   --holefill <ITERATIONS> - Enable mask hole-filling with specified dilation/erosion iterations
#
# Arguments:
#   INPUT_DIR  - Path to input BIDS directory containing subject data
#   OUTPUT_DIR - Path to output directory for processed results  
#   SUBJECT*   - One or more subject identifiers (e.g., sub-001, sub-002)
#
# The script will:
#   1. Check each subject directory for session subdirectories
#   2. Verify that sessions contain 'anat' directories with .nii files
#   3. Submit SLURM jobs for valid subject/session combinations in parallel
#

# Check if sufficient arguments are provided and parse options
ACQ_TYPES="PDw,T1w,MTw"
NO_CSF="false"
HOLEFILL="false"
HOLEFILL_ITERATIONS=""

# Save the original command line before any parsing
ORIGINAL_COMMAND="$0 $*"

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --acqs)
            ACQ_TYPES="$2"
            shift 2
            ;;
        --no-csf)
            NO_CSF="true"
            shift
            ;;
        --holefill)
            HOLEFILL="true"
            HOLEFILL_ITERATIONS="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Usage: $0 [--acqs <ACQ_TYPES>] [--no-csf] [--holefill <ITERATIONS>] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ..."
            echo "Options:"
            echo "  --acqs <ACQ_TYPES>      Comma-separated acquisition types (default: PDw,T1w,MTw)"
            echo "  --no-csf                Exclude CSF from brain mask"
            echo "  --holefill <ITERATIONS> Enable mask hole-filling"
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
    echo "Usage: $0 [--acqs <ACQ_TYPES>] [--no-csf] [--holefill <ITERATIONS>] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ..."
    echo "Options:"
    echo "  --acqs <ACQ_TYPES>      Comma-separated acquisition types (default: PDw,T1w,MTw)"
    echo "  --no-csf                Exclude CSF from brain mask"
    echo "  --holefill <ITERATIONS> Enable mask hole-filling"
    echo "Example: $0 /path/to/input /path/to/output sub-001 sub-002 sub-003"
    echo "Example: $0 --acqs PDw,T1w /path/to/input /path/to/output sub-001 sub-002"
    echo "Example: $0 --no-csf /path/to/input /path/to/output sub-001 sub-002"
    echo "Example: $0 --holefill 7 /path/to/input /path/to/output sub-001 sub-002"
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

# Save the full command used to call this script
COMMAND_FILE="${OUTPUT_DIR}/synthstrip_command.txt"
echo "Command executed on $(date):" > "$COMMAND_FILE"
echo "$ORIGINAL_COMMAND" >> "$COMMAND_FILE"
echo "" >> "$COMMAND_FILE"
echo "Full command with options:" >> "$COMMAND_FILE"
echo "  Input Directory: $INPUT_DIR" >> "$COMMAND_FILE"
echo "  Output Directory: $OUTPUT_DIR" >> "$COMMAND_FILE"
echo "  Acquisition Types: $ACQ_TYPES" >> "$COMMAND_FILE"
echo "  Exclude CSF: $NO_CSF" >> "$COMMAND_FILE"
echo "  Hole-filling: $HOLEFILL" >> "$COMMAND_FILE"
if [ "$HOLEFILL" = "true" ]; then
    echo "  Hole-filling iterations: $HOLEFILL_ITERATIONS" >> "$COMMAND_FILE"
fi
echo "  Subjects: $@" >> "$COMMAND_FILE"
echo "" >> "$COMMAND_FILE"

echo "Command saved to: $COMMAND_FILE"

# SLURM configuration
SLURM_PARTITIONS="short,group_servers,gr_weiskopf"
SLURM_SCRIPT="/data/u_kuegler_software/git/qsm/run_qsmxt/synthstrip_slurm.sh"

echo "Input Directory: $INPUT_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Acquisition Types: $ACQ_TYPES"
echo "Exclude CSF: $NO_CSF"
echo "Hole-filling: $HOLEFILL"
if [ "$HOLEFILL" = "true" ]; then
    echo "Hole-filling iterations: $HOLEFILL_ITERATIONS"
fi
echo "Subjects to process: $@"
echo "============================================="

# Initialize job tracking
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
                jobid=$(sbatch -p ${SLURM_PARTITIONS} ${SLURM_SCRIPT} "$INPUT_DIR" "$OUTPUT_DIR" "$subj" "$session" "$ACQ_TYPES" "$NO_CSF" "$HOLEFILL" "$HOLEFILL_ITERATIONS" | awk '{print $4}')
                echo "  Submitted batch job $jobid for ${subj}/${session}"
                ((total_jobs++))
            else
                echo "  Skipping session: $session (no anat directory with .nii or .nii.gz files found)"
            fi
        fi
    done < <(find "${subj_dir}" -maxdepth 1 -name "ses-*" -type d -print0 2>/dev/null)
    
    # If no session directories found, check for anat directory directly in subject directory
    if [ "$sessions_found" = false ]; then
        anat_dir="${subj_dir}/anat"
        if [ -d "$anat_dir" ] && [ -n "$(find "$anat_dir" -name "*.nii" -o -name "*.nii.gz" 2>/dev/null)" ]; then
            sessions_found=true
            echo "  Found anatomical data directly in subject directory (no session directories)"
            
            # Submit SLURM job for this subject without session (empty string for session parameter)
            jobid=$(sbatch -p ${SLURM_PARTITIONS} ${SLURM_SCRIPT} "$INPUT_DIR" "$OUTPUT_DIR" "$subj" "" "$ACQ_TYPES" "$NO_CSF" "$HOLEFILL" "$HOLEFILL_ITERATIONS" | awk '{print $4}')
            echo "  Submitted batch job $jobid for ${subj} (no session)"
            ((total_jobs++))
        fi
    fi
    
    if [ "$sessions_found" = false ]; then
        echo "  Warning: No valid sessions found for subject $subj"
    fi
    
    echo ""
done

echo "============================================="
echo "Total jobs submitted: $total_jobs"
if [ $total_jobs -gt 0 ]; then
    echo "Monitor progress with: squeue -u \$USER"
fi
