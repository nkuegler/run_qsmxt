# run_qsmxt
A repository to QSMxT for a batch of subject/sessions


> **Important hint: QSMxT seems to not run on the SLURM node drachenkopf (probably due to incompatibility of the QSMxT container and the installed EPYC CPU). This node is therefore excluded in the sbatch command using the -x flag!**

## How to run 

- adjust properties of the qsmxt command in `qsmxt_slurm.sh`

```
getserver -sb

cd /path/to/output/dir
# before the qsmxt command is executed, the singularity container is made available by sourcing `bash.singularity` (custom file) and the correct conda environment is activated after sourcing `bash.conda` (custom file)

/data/u_kuegler_software/git/qsm/run_qsmxt/call_qsmxt_n.sh input_dir output_dir sub-001 sub-002 sub-003
```

> Note: it is important to specify the session's name, not only the subject's name. Otherwise, the execution of `call_qsmxt.sh` raises an error in the romeo_combine_phase step *(this only works if there are no session directories in the subject directory)*.

> Note: These scripts are proprietary, as they require some custom files for making the singularity container and conda available


### Command for IronSleep Data
```
# sbatch on slurm
./call_qsmxt_n.sh --seq /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr/ /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr_QSMxT/20250714_qsmxt_pdf/ sub-001

# not slurm:
qsmxt /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr/ \
    /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr_QSMxT/20250714_qsmxt_pdf/ \
    --premade 'gre' \
    --do_qsm \
    --do_swi \
    --labels_file '/data/u_kuegler_software/miniforge3/envs/qsmxt8/lib/python3.8/site-packages/qsmxt/aseg_labels.csv' \
    --recs rec-loraksRsos \  
    --acqs acq-T1w acq-PDw acq-MTw \  
    --bf_algorithm 'pdf' \
    --auto_yes
```

## Brain Extraction with SynthStrip

The repository includes scripts for batch brain extraction using FreeSurfer's `mri_synthstrip`.

### Usage

```bash
./call_synthstrip.sh [--acqs <ACQ_TYPES>] [--no-csf] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ...
```

**Options:**
- `--acqs <ACQ_TYPES>` - Comma-separated acquisition types (default: `PDw,T1w,MTw`)
- `--no-csf` - Exclude CSF from brain mask

**Features:**
- Automatically discovers sessions with anatomical data
- Processes multiple acquisition types (PDw, T1w, MTw)
- Matches files with `echo-01` or `echo-1` naming conventions
- GPU acceleration (auto-detected)
- Generates both brain-extracted images (`_brain.nii`) and masks (`_mask.nii`)
- Parallel job submission by default
- Warning when multiple matching files found per acquisition type (processes all)

### Examples

```bash
# Process all subjects with default acquisition types
./call_synthstrip.sh /path/to/input /path/to/output sub-001 sub-002 sub-003

# Custom acquisition types with CSF exclusion
./call_synthstrip.sh --acqs PDw,T1w --no-csf /path/to/input /path/to/output sub-001 sub-002

# IronSleep data example
./call_synthstrip.sh \
  /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr \
  /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr/derivatives/synthstrip \
  sub-001 sub-002
```

> **Note:** SynthStrip works on all SLURM nodes (no node exclusions needed).
