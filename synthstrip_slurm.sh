#!/bin/bash

#
# SynthStrip SLURM Job Script
# 
# This script runs FreeSurfer's mri_synthstrip for brain extraction
# on a SLURM cluster for a single subject/session.
#
# Usage: sbatch synthstrip_slurm.sh <INPUT_DIR> <OUTPUT_DIR> <SUBJECT> [SESSION] <ACQ_TYPES> [NO_CSF] [HOLEFILL] [HOLEFILL_ITERATIONS]
#
# Arguments:
#   INPUT_DIR           - Path to input BIDS directory containing raw data
#   OUTPUT_DIR          - Path to output directory for processed results
#   SUBJECT             - Subject identifier (e.g., sub-001)
#   SESSION             - (Optional) Session identifier (e.g., ses-01) (pass empty string if none)
#   ACQ_TYPES           - Comma-separated list of acquisition types (e.g., PDw,T1w,MTw)
#   NO_CSF              - (Optional) Set to 'true' to exclude CSF from brain mask
#   HOLEFILL            - (Optional) Set to 'true' to enable mask hole-filling
#   HOLEFILL_ITERATIONS - (Optional) Number of dilation/erosion iterations for hole-filling
#
# The script processes anatomical data using mri_synthstrip with the following features:
#   - Brain extraction for specified acquisition types
#   - GPU acceleration (if available)
#   - Generates both brain-extracted images (_brain.nii) and masks (_mask.nii)
#
# Output is placed in OUTPUT_DIR maintaining BIDS structure.
#

#SBATCH -c 8
#SBATCH --mem 32G
#SBATCH --time 60
#SBATCH -o /data/u_kuegler_software/git/qsm/run_qsmxt/logs/%j_synthstrip.out

# Software versions
FREESURFER_VERSION="7.4.1"
FSL_VERSION="6.0.6"

INPUT_DIR="$1"
OUTPUT_DIR="$2"
SUBJECT="$3"
SESSION="$4"
ACQ_TYPES="$5"
NO_CSF="${6:-false}"
HOLEFILL="${7:-false}"
HOLEFILL_ITERATIONS="$8"

echo "Input Directory: ${INPUT_DIR}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "Subject: ${SUBJECT}"
if [[ -n "$SESSION" ]]; then
    echo "Session: ${SESSION}"
else
    echo "Session: Not specified (processing subject without session directory)"
fi
echo "Acquisition Types: ${ACQ_TYPES}"
echo "Exclude CSF: ${NO_CSF}"
echo "Hole-filling: ${HOLEFILL}"
if [ "$HOLEFILL" = "true" ]; then
    echo "Hole-filling iterations: ${HOLEFILL_ITERATIONS}"
fi
echo "--------"

# Check for GPU availability
GPU_FLAG=""
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo "GPU detected - using GPU acceleration"
    GPU_FLAG="--gpu"
else
    echo "No GPU detected - using CPU only"
fi

# Set CSF flag
CSF_FLAG=""
if [ "$NO_CSF" = "true" ]; then
    echo "CSF exclusion enabled"
    CSF_FLAG="--no-csf"
fi

# Convert comma-separated acquisition types to array
IFS=',' read -ra ACQ_ARRAY <<< "$ACQ_TYPES"

# Construct paths - handle optional session
if [[ -n "$SESSION" ]]; then
    INPUT_ANAT_DIR="${INPUT_DIR}/${SUBJECT}/${SESSION}/anat"
    OUTPUT_ANAT_DIR="${OUTPUT_DIR}/${SUBJECT}/${SESSION}/anat"
    PROCESSING_MSG="${SUBJECT}/${SESSION}"
else
    INPUT_ANAT_DIR="${INPUT_DIR}/${SUBJECT}/anat"
    OUTPUT_ANAT_DIR="${OUTPUT_DIR}/${SUBJECT}/anat"
    PROCESSING_MSG="${SUBJECT}"
fi

# Create output directory
mkdir -p "${OUTPUT_ANAT_DIR}"

echo "Processing brain extraction for ${PROCESSING_MSG}..."

# Process each acquisition type
for acq in "${ACQ_ARRAY[@]}"; do
    echo "  Processing acquisition type: ${acq}"
    
    # First pass: count matching files
    matching_files=()
    for input_file in "${INPUT_ANAT_DIR}"/*_acq-${acq}*_echo-{01,1}_*_part-mag*.nii*; do
        if [ -f "$input_file" ]; then
            matching_files+=("$input_file")
        fi
    done
    
    # Warn if multiple files found
    if [ ${#matching_files[@]} -gt 1 ]; then
        echo "    Warning: Found ${#matching_files[@]} files for acquisition type ${acq} - processing all"
    fi
    
    # Process each matching file
    files_processed=0
    for input_file in "${matching_files[@]}"; do
        if [ -f "$input_file" ]; then
            files_processed=$((files_processed + 1))
            
            # Get the base filename without extension
            basename_file=$(basename "$input_file")
            # Remove .nii.gz or .nii extension
            if [[ "$basename_file" == *.nii.gz ]]; then
                base="${basename_file%.nii.gz}"
                ext=".nii.gz"
            else
                base="${basename_file%.nii}"
                ext=".nii"
            fi
            
            # Construct output filenames
            output_brain="${OUTPUT_ANAT_DIR}/${base}_brain${ext}"
            output_mask="${OUTPUT_ANAT_DIR}/${base}_mask${ext}"
            
            echo "    Processing: $basename_file"
            
            # Run mri_synthstrip
            SCWRAP freesurfer ${FREESURFER_VERSION} \
            mri_synthstrip \
                -i "$input_file" \
                -o "$output_brain" \
                -m "$output_mask" \
                $GPU_FLAG \
                $CSF_FLAG
            
            if [ $? -eq 0 ]; then
                echo "    Success: Created brain and mask files"
                echo "    --------"
                
                # Run hole-filling if requested
                if [ "$HOLEFILL" = "true" ]; then
                    echo "Performing hole-filling with ${HOLEFILL_ITERATIONS} dilation/erosion iterations..."
                    
                    # Build the fslmaths command with specified iterations
                    cmd="SCWRAP fsl ${FSL_VERSION} fslmaths \"$output_mask\" -kernel sphere 1"
                    
                    # Add dilation operations
                    for ((i=1; i<=HOLEFILL_ITERATIONS; i++)); do
                        cmd="$cmd -dilM"
                    done
                    
                    # Add erosion operations
                    for ((i=1; i<=HOLEFILL_ITERATIONS; i++)); do
                        cmd="$cmd -ero"
                    done
                    
                    # Overwrite the original mask
                    cmd="$cmd \"$output_mask\""
                    
                    # Execute the hole-filling command
                    eval $cmd
                    
                    if [ $? -eq 0 ]; then
                        echo "    Success: Created filled mask"
                        
                        # Decompress mask if FSL created .nii.gz
                        if [ -f "${output_mask}.gz" ]; then
                            echo "Decompressing mask..."
                            gunzip -f "${output_mask}.gz"
                        fi
                        
                        # Apply the filled mask to the input file to create new brain image
                        echo "Applying filled mask to input image..."
                        SCWRAP fsl ${FSL_VERSION} fslmaths "$input_file" -mas "$output_mask" "$output_brain"
                        
                        if [ $? -eq 0 ]; then
                            echo "    Success: Created new brain image using filled mask"
                            
                            # Decompress brain if FSL created .nii.gz
                            if [ -f "${output_brain}.gz" ]; then
                                echo "Decompressing brain..."
                                gunzip -f "${output_brain}.gz"
                            fi
                        else
                            echo "    Error: Failed to apply filled mask to input image"
                        fi
                    else
                        echo "    Error: Failed to perform hole-filling"
                    fi
                fi
            else
                echo "    Error: Failed to process $basename_file"
            fi
        fi
    done
    
    if [ $files_processed -eq 0 ]; then
        echo "    Warning: No files processed for acquisition type ${acq}"
    else
        echo "    Processed $files_processed file(s) for acquisition type ${acq}"
    fi
    echo "--------"
done

echo "--------"
echo "Brain extraction completed for ${PROCESSING_MSG}"
