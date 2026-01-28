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
./call_synthstrip.sh [--acqs <ACQ_TYPES>] [--no-csf] [--holefill <ITERATIONS>] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ...
```

**Options:**
- `--acqs <ACQ_TYPES>` - Comma-separated acquisition types (default: `PDw,T1w,MTw`)
- `--no-csf` - Exclude CSF from brain mask
- `--holefill <ITERATIONS>` - Enable mask hole-filling with specified dilation/erosion iterations

**Features:**
- Automatically discovers sessions with anatomical data
- Processes multiple acquisition types (PDw, T1w, MTw)
- Matches files with `echo-01` or `echo-1` naming conventions
- GPU acceleration (auto-detected)
- Generates both brain-extracted images (`_brain.nii`) and masks (`_mask.nii`)
- **Saves execution command** to `synthstrip_command.txt` in the output directory for reproducibility
- **Optional morphological hole-filling** of masks using FSL's fslmaths:
  - Performed directly within the same SLURM job after mask creation
  - Uses successive dilation and erosion operations (configurable number of iterations)
  - Overwrites original mask with filled version
  - Re-applies filled mask to input image, updating `_brain.nii` output
- Parallel job submission by default
- Warning when multiple matching files found per acquisition type (processes all)

### Examples

```bash
# Process all subjects with default acquisition types
./call_synthstrip.sh /path/to/input /path/to/output sub-001 sub-002 sub-003

# Custom acquisition types with CSF exclusion
./call_synthstrip.sh --acqs PDw,T1w --no-csf /path/to/input /path/to/output sub-001 sub-002

# With hole-filling (7 iterations)
./call_synthstrip.sh --holefill 7 /path/to/input /path/to/output sub-001 sub-002

# Combine multiple options
./call_synthstrip.sh --acqs PDw,T1w --no-csf --holefill 5 /path/to/input /path/to/output sub-001

# IronSleep data example
./call_synthstrip.sh \
  /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr \
  /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr/derivatives/synthstrip \
  sub-001 sub-002
```

> **Note:** SynthStrip works on all SLURM nodes (no node exclusions needed). When hole-filling is enabled, the original `_mask.nii` file is overwritten with the filled version, and the `_brain.nii` file is regenerated using the filled mask.


# Example synthstrip

```
subjs=$(find /data/pt_02262/data/liege_data/bids/derivatives/LORAKS/derivatives/LCPCA_distCorr/ -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort -V | tr '\n' ' ')

./call_synthstrip.sh --no-csf --holefill 7 /data/pt_02262/data/liege_data/bids/derivatives/LORAKS/derivatives/LCPCA_distCorr/ /data/pt_02262/data/liege_data/bids/derivatives/LORAKS/derivatives/LCPCA_distCorr/derivatives/synthstrip/ $subjs

./call_qsmxt_n.sh --transform-to-orig /data/pt_02262/data/liege_data/bids/derivatives/LORAKS/derivatives/LCPCA_distCorr/ /data/pt_02262/data/liege_data/bids/derivatives/LORAKS/derivatives/QSMxT/20251228_qsmxt_pdf_synthstripFilled/ $subjs 
```

## Spatial Transformations

The repository includes scripts for transforming QSMxT outputs to different spatial reference frames.

### Transform to Original Space

Transform QSMxT outputs back to the original input acquisition space using `transform_to_orig.sh` or the `--transform-to-orig` flag in `call_qsmxt_n.sh`.

**Integrated workflow (recommended):**
```bash
# Transform outputs during QSMxT processing
./call_qsmxt_n.sh --transform-to-orig <INPUT_DIR> <OUTPUT_DIR> <SUBJECTS...>
```

**Standalone script:**
```bash
# Transform already processed outputs
./deprecated_transform_to_orig.sh <QSMXT_OUTPUT_DIR> <ORIGINAL_INPUT_DIR>
```

Creates `transform_to_orig/` subdirectories containing outputs aligned to original acquisition space. Uses FSL flirt with sform-based transformation.

### Transform to MPM Space

Transform Chimap outputs to co-registered MPM reference space using `deprecated_transform_to_mpm.sh`. This aligns QSMxT-derived Chimaps with acquisitions that have been co-registered to PDw space via SPM.

```bash
./deprecated_transform_to_mpm.sh <QSMXT_OUTPUT_DIR> <MPM_REFERENCE_DIR>
```

Creates `transform_to_mpm/` subdirectories with T1w and MTw Chimaps aligned to their corresponding co-registered references. Uses FSL flirt with spline interpolation.

> **Note:** The `transform_to_orig` functionality is integrated into `qsmxt_slurm_n.sh` via the `--transform-to-orig` flag. The `deprecated_transform_to_mpm.sh` script is currently standalone but may be integrated as a separate SLURM job in future versions (see following note for concerns).


> **Note:** The transformation to the mpm space using the original coregistrations of the hMRI toolbox (from MPMCalc directory) turned out to be problematic as the resulting sforms/qforms of the T1w and MTw Chimaps differ from the PDw Chimap (MPM reference space). This makes it more difficult to process and inspect them further. 
> To avoid this, I instead run a separate rigid-body registration using SPM to align the T1w and MTw Chimaps to the PDw Chimap (see `transform_toPDw_SPM.sh`)."



# ToDo

- Implement option to clean up the supplementary directory at the end of each job (and a final clean-up at the end of all jobs)
- (not sure) Integrate `transform_to_mpm.sh` into the SLURM workflow as a separate job -> maybe rather integrate the second SPM registration