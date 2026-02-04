#!/bin/bash

#SBATCH --job-name=average_chimaps
#SBATCH -c 4
#SBATCH --mem=4G
#SBATCH --time 30
#SBATCH -o /data/u_kuegler_software/git/qsm/run_qsmxt/logs/%j_avgChimaps.out

#
# Merge and Average Chimaps using FSL
#
# This script averages three Chimap files (PDw reference, coregistered T1w, coregistered MTw)
# by merging them along the time dimension and computing their temporal mean using FSL tools.
#
# Usage: sbatch average_chimaps_slurm.sh <PDW_REF_FILE> <T1W_COREG_FILE> <MTW_COREG_FILE> <OUTPUT_DIR>
#
# Arguments:
#   PDW_REF_FILE    - Path to the PDw reference Chimap
#   T1W_COREG_FILE  - Path to the coregistered T1w Chimap
#   MTW_COREG_FILE  - Path to the coregistered MTw Chimap
#   OUTPUT_DIR      - Directory where merged and mean files will be saved
#
# Output files:
#   <subject>_<session>_merged_Chimap.nii - Concatenated 4D volume of all three Chimaps
#   <subject>_<session>_mean_Chimap.nii     - Temporal mean across the three Chimaps
#
# This script is typically called as a dependent SLURM job by coreg_toPDw_SPM.sh after
# both coregistration jobs complete successfully.

# Check arguments
if [ $# -ne 4 ]; then
    echo "Error: Incorrect number of arguments"
    echo "Usage: $0 <REF_FILE> <T1W_COREG_FILE> <MTW_COREG_FILE> <OUTPUT_DIR>"
    exit 1
fi

PDW_REF_FILE="$1"
T1W_COREG_FILE="$2"
MTW_COREG_FILE="$3"
OUTPUT_DIR="$4"

FSL_VERSION="6.0.6"

echo "============================================="
echo "Merge and Average Chimaps"
echo "============================================="
echo "PDw reference file: $PDW_REF_FILE"
echo "T1w coregistered: $T1W_COREG_FILE"
echo "MTw coregistered: $MTW_COREG_FILE"
echo "Output directory: $OUTPUT_DIR"
echo "============================================="

# Verify all input files exist
if [ ! -f "$PDW_REF_FILE" ]; then
    echo "Error: Reference file not found: $PDW_REF_FILE"
    exit 1
fi

if [ ! -f "$T1W_COREG_FILE" ]; then
    echo "Error: T1w coregistered file not found: $T1W_COREG_FILE"
    exit 1
fi

if [ ! -f "$MTW_COREG_FILE" ]; then
    echo "Error: MTw coregistered file not found: $MTW_COREG_FILE"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Extract session identifier from reference file for output naming
ref_basename=$(basename "$PDW_REF_FILE")
# Extract subject and session info (e.g., sub-001_ses-13)
subj_ses=$(echo "$ref_basename" | grep -oP 'sub-[0-9]+_ses-[0-9]+')

if [ -z "$subj_ses" ]; then
    echo "Warning: Could not extract subject/session from filename, using generic names"
    merged_output="$OUTPUT_DIR/merged_Chimap"
    mean_output="$OUTPUT_DIR/mean_Chimap"
else
    merged_output="${OUTPUT_DIR}/${subj_ses}_merged_Chimap"
    mean_output="${OUTPUT_DIR}/${subj_ses}_mean_Chimap"
fi

echo ""
echo "Output files will be named:"
echo "  Merged: ${merged_output}.nii"
echo "  Mean: ${mean_output}.nii"
echo ""

# Merge the three Chimap files along the time dimension
echo "Step 1: Merging Chimaps..."
SCWRAP fsl $FSL_VERSION fslmerge -t "$merged_output" "$PDW_REF_FILE" "$T1W_COREG_FILE" "$MTW_COREG_FILE"

if [ $? -ne 0 ]; then
    echo "Error: fslmerge failed"
    exit 1
fi
echo "  Success: Created ${merged_output}.nii.gz"

# Compute the temporal mean
echo "Step 2: Computing mean..."
SCWRAP fsl $FSL_VERSION fslmaths "${merged_output}.nii.gz" -Tmean "$mean_output"

if [ $? -ne 0 ]; then
    echo "Error: fslmaths failed"
    exit 1
fi
echo "  Success: Created ${mean_output}.nii.gz"

# Uncompress the output files
echo "Step 3: Uncompressing files..."
gunzip "${merged_output}.nii.gz"
if [ $? -eq 0 ]; then
    echo "  Success: Uncompressed ${merged_output}.nii.gz"
else
    echo "  Warning: Failed to uncompress ${merged_output}.nii.gz"
fi

gunzip "${mean_output}.nii.gz"
if [ $? -eq 0 ]; then
    echo "  Success: Uncompressed ${mean_output}.nii.gz"
else
    echo "  Warning: Failed to uncompress ${mean_output}.nii.gz"
fi

echo ""
echo "============================================="
echo "Merge and Average Complete"
echo "============================================="
echo "Output files:"
echo "  $(ls -lh ${merged_output}.nii 2>/dev/null || echo 'Merged file not found')"
echo "  $(ls -lh ${mean_output}.nii 2>/dev/null || echo 'Mean file not found')"
echo "============================================="
