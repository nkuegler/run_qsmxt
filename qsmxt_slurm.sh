#!/bin/bash

#
#SBATCH -c 32	
#SBATCH --mem 200G	
#SBATCH --time 90	
#SBATCH -o /data/p_03037/LORAKS/bids/derivatives/qsm/code/logs/%j.out	# redirect the output
#

SUBJECT="$1"

INPUT_DIR=/data/p_03037/LORAKS/bids/derivatives/LORAKS
OUTPUT_DIR=/data/p_03037/LORAKS/bids/derivatives/qsm/qsmxt_allSubj
SUPPL_DIR=${OUTPUT_DIR}/supplementary
mkdir -p ${SUPPL_DIR/$SUBJECT}


qsmxt $INPUT_DIR \
    $SUPPL_DIR/$SUBJECT \
    --premade 'gre' \
    --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' \
    --subjects "${SUBJECT}" \
    --recs rec-loraks \
    --acqs acq-T1w acq-MTw acq-PDw \
    --use_existing_masks \
    --existing_masks_pipeline 'synthstrip' \
    --auto_yes

    #--sessions ses-01 \

if [ $? -eq 0 ]; then
    mv "${SUPPL_DIR}/${SUBJECT}" "${OUTPUT_DIR}/"
fi