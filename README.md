# run_qsmxt

Batch processing scripts for [QSMxT](https://qsmxt.github.io/QSMxT/) (Quantitative Susceptibility Mapping) on a SLURM cluster. This repository provides wrapper scripts to submit and manage QSMxT jobs, optional brain extraction with FREESURFER's SynthStrip for skull stripping, spatial transformations back to original acquisition space, and multi-contrast Chimap coregistration and averaging.

*These scripts are designed to work with Multi-Parameter Mapping (MPM) data (multiple contrasts: T1w, PDw, MTw) but can be re-purposed for other data by adjusting the acquisition file patterns and contrast-specific parameters in the SLURM scripts.*

> **Note:** These scripts are designed for a specific SLURM cluster environment and require custom shell configurations (`bash.singularity`, `bash.conda`) to make Singularity containers available and initialize Conda.

## Installation

Please refer to the [QSMxT documentation](https://qsmxt.github.io/QSMxT/installation) for installation instructions. The QSMxT developers provide a Singularity container that includes all necessary dependencies, which is the recommended way to run QSMxT on a cluster. As the container and the software are updated regularly, it's best to follow the official installation guide to ensure compatibility. 

**Here you can find instructions how I set up QSMxT on my machine using Singularity and Conda. These instructions are outdated and the specified container does not work anymore! The newest version requires `apptainer` instead of `singularity`.**

You can either use the QSMxT in [Neurodesk](https://www.neurodesk.org/docs/getting-started/neurocommand/linux-and-hpc/) or install the singularity container by itself ([see HPC installation](https://qsmxt.github.io/QSMxT/installation#quickstart-via-neurodesk)). I used the latter, which is described below.

Either way, run the installation in a conda environment. [See this page](https://wiki.cbs.mpg.de/spaces/CBSNP/pages/158105663/Setting+up+Conda) for instructions on how to set this up (restricted access)..
+ **ATTENTION:** If you are part of the MPI CBS infrastructure, make sure that you did **NOT** install miniforge in your home directory. It is too small so that the installation is likely to fail. Follow the link above to learn how to install it in your personal software directory.

### QSMxT container

> **For MPI CBS members:** 
> > Apptainer is not available in the MPI CBS IT infrastructure and the mentioned singularity build does not work anymore. You can find the pre-built QSMxT singularity container in `/data/p_gr_weiskopf_software/singularity/qsmxt_8.0.2_20250403/`. You must use this instead of installing the container yourself. 
> > + **What does this mean for you?**
> >     + You don't need to clone the QSMxT repository.
> >     + You still need to create and define the singularity `cache` and `tmp` directories as described below.
> >     + You still need to set up the conda environment as described below.

\
For installation of the transparent singularity container, follow the steps below (adapted from HPC installation [on this website](https://qsmxt.github.io/QSMxT/installation#quickstart-via-neurodesk)).

**Steps from the website above (version: 2025-01-21):**
QSMxT can be installed on an HPC or Linux machine using [transparent singularity](https://github.com/neurodesk/transparent-singularity). Transparent singularity installs QSMxT using an Apptainer (or in my case Singularity) container and exposes the underlying tools to the host environment, which is necessary for HPCs using PBS Graph or SLURM.

### First things first:
You must have sufficient storage available in `$SINGULARITY_TMPDIR` (by default `/tmp`), `$SINGULARITY_CACHEDIR` (by default `$HOME/.singularity/cache`), and the repository directory to store the QSMxT container. **Make sure to define these paths before building the container.** I used a small bash script which I call before building and every time before running the container (optionally, you can add these lines to your `.bashrc`):

```
######### define singularity cache and tmp directories and add container to $PATH ###############
export SINGULARITY_TMPDIR=/data/u_kuegler_software/singularity/tmp
export SINGULARITY_CACHEDIR=/data/u_kuegler_software/singularity/cache
echo ">>> Making Singularity containers available"
# Container in /data/u_kuegler_software/git/qsmxt_8.0.2_20250403
export PATH=/data/u_kuegler_software/git/qsmxt_8.0.2_20250403:$PATH

# if you are part of the MPI CBS, you have to replace the last line of the code block above by:
# export PATH=/data/p_gr_weiskopf_software/singularity/qsmxt_8.0.2_20250403:$PATH
```

### Now, the installation:
1. Install or load Singularity or Apptainer on your HPC. Test if it works by executing `singularity --version`.
2. Install the QSMxT container via transparent singularity:
```
git clone https://github.com/NeuroDesk/transparent-singularity qsmxt_8.0.2_20250403
cd qsmxt_8.0.2_20250403
./run_transparent_singularity.sh --container qsmxt_8.0.2_20250403.simg
source activate_qsmxt_8.0.2_20250403.simg.sh
```
> **Note:** QSMxT switched from Singularity to Apptainer a while ago. Those are essentially the same, but if your cluster only has Singularity (as in my case), you can still need to adjust the build command provided in the QSMxT docs for Singularity.

> **Important:** Please refer to the official QSMxT documentation for building the newest container possible, as older container versions may not be available anymore. I hope that the adjustment from transparent_apptainer to transparent_singularity will keep working.

### Create a conda environment
1. Check if Miniforge is installed and initialized using `which conda`. 
2. If so, create a new conda environment and install QSMxT in it:
```
#create conda environment for qsmxt
conda create -n qsmxt8 python=3.8
conda activate qsmxt8
pip install qsmxt==8.0.2
```

> [!IMPORTANT]
> Now you should be able to run QSMxT commands in this conda environment, and the container will be automatically used when you execute `qsmxt` commands. Make sure to activate the conda environment and to add the container path to your `$PATH` before using qsmxt!

## Quick Start

1. **Run QSMxT** with the `--transform-to-orig` flag to process subjects and transform outputs back to original acquisition space:

   ```bash
   ./call_qsmxt_n.sh --transform-to-orig <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ...
   ```

2. **Average Chimaps** across contrasts once QSMxT processing is complete. This coregisters T1w and MTw Chimaps to PDw space and computes the mean:

   ```bash
   ./call_coreg_toPDw.sh [--pdw-t1w-only] <OUTPUT_DIR>
   ```

   This submits coregistration jobs for each subject/session and automatically queues a dependent averaging job using `average_chimaps_slurm.sh`.

## Usage

### QSMxT Processing (`call_qsmxt_n.sh`)

The main entry point for batch QSMxT processing. It discovers sessions with `anat/` data and submits SLURM jobs for each subject/session combination.

```bash
./call_qsmxt_n.sh [--seq] [--transform-to-orig] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ...
```

**Arguments:**

| Argument     | Description                                           |
| ------------ | ----------------------------------------------------- |
| `INPUT_DIR`  | Path to input BIDS directory containing subject data  |
| `OUTPUT_DIR` | Path to output directory for processed results        |
| `SUBJECT*`   | One or more subject identifiers (e.g., `sub-001`)     |

**Options:**

| Option                | Description                                                               |
| --------------------- | ------------------------------------------------------------------------- |
| `--seq`               | Process jobs sequentially (with SLURM dependencies). Default is parallel. |
| `--transform-to-orig` | Transform outputs back to original input space using FSL flirt.           |

**What it does:**

1. Checks each subject directory for session subdirectories (or a direct `anat/` directory).
2. Verifies that sessions contain `anat` directories with `.nii` or `.nii.gz` files.
3. Submits SLURM jobs via `qsmxt_slurm_n.sh` for valid subject/session combinations.
4. By default, all jobs run in parallel. Use `--seq` to chain them with dependencies.

**SLURM job details** (`qsmxt_slurm_n.sh`):
This defines the actual QSMxT processing command. Adjust this script to customize the QSM pipeline.

- Runs QSMxT with the `gre` premade configuration.
- Performs QSM reconstruction (Phase-based masking, ROMEO phase unwrapping, PDF background field removal), SWI processing, and R2* mapping.
- Processes acquisitions: `acq-T1w`, `acq-PDw`, `acq-MTw` with `rec-loraksRsos`.
- When `--transform-to-orig` is set, all output NIfTI files are transformed back to their corresponding original input space using FSL flirt with sform-based transformation (not a co-registration). Transformed files are placed in a `transform_to_orig/` subdirectory.
- Temporary Results are initially placed in a `Supplementary/` directory and moved to the final output location upon successful completion.

> **Important for MPI CBS members:** QSMxT does not run on the SLURM node `drachenkopf` (likely due to incompatibility of the AMD EPYC CPU the QSMxT container). This node is automatically excluded via the `-x` flag.

**Example:**
*(automatically called by the SLURM job submission script)*

```bash
./call_qsmxt_n.sh --transform-to-orig /path/to/bids/input /path/to/output sub-001 sub-002 sub-003
```

### Brain Extraction with SynthStrip (Optional)

The repository includes scripts for batch brain extraction using FreeSurfer's `mri_synthstrip`. This step is **optional** — if you use pre-computed brain masks, you need to pass additional flags to the QSMxT SLURM script.

#### Running SynthStrip

```bash
./call_synthstrip.sh [OPTIONS] <INPUT_DIR> <OUTPUT_DIR> <SUBJECT1> [SUBJECT2] ...
```

**Options:**

| Option                    | Description                                                                |
| ------------------------- | -------------------------------------------------------------------------- |
| `--acqs <ACQ_TYPES>`      | Comma-separated acquisition types (default: `PDw,T1w,MTw`)                |
| `--no-csf`                | Exclude CSF from brain mask                                                |
| `--holefill <ITERATIONS>` | Enable mask hole-filling with specified dilation/erosion iterations         |
| `--separate-masks`        | Create separate brain masks for each acquisition type (see below)          |

**Default behavior (shared mask mode):**
Only the reference contrast (T1w by default) is processed with `mri_synthstrip`. For other acquisition types (PDw, MTw), symbolic links are created pointing to the T1w mask, and brain-extracted images are generated by applying that mask. This ensures consistent brain extraction across all contrasts while saving computation time.

> **Warning:** There may be slight misregistration between T1w and other contrasts as they come from separate sequences. No explicit co-registration is performed. Use `--separate-masks` if brain alignment across contrasts is poor.

**Separate masks mode** (`--separate-masks`): Each acquisition type is independently processed with `mri_synthstrip`, creating unique masks for each contrast.

The reference contrast can be changed by editing `REF_BRAIN_MASK_CONTRAST` in `synthstrip_slurm.sh` (default: `T1w`).

**Features:**

- GPU acceleration (auto-detected)
- Generates both brain-extracted images (`_brain.nii`) and masks (`_mask.nii`)
- Optional morphological hole-filling using FSL's `fslmaths` (dilation + erosion)
- Saves the execution command to `synthstrip_command.txt` in the output directory
- Parallel job submission

**Example:**

```bash
./call_synthstrip.sh --no-csf --holefill 7 /path/to/input /path/to/synthstrip_output sub-001 sub-002
```

#### Using SynthStrip Masks with QSMxT

To use pre-computed SynthStrip brain masks in QSMxT, you need to uncomment or add the following flags in `qsmxt_slurm_n.sh`:

```bash
--use_existing_masks \
--existing_masks_pipeline 'synthstrip' \
```

These flags tell QSMxT to look for existing brain masks (produced by the SynthStrip pipeline) instead of computing its own.

### Chimap Coregistration and Averaging (`call_coreg_toPDw.sh`)

After QSMxT processing with `--transform-to-orig`, you can coregister the multi-contrast Chimaps (magnetic susceptibility maps) to a common reference space and average them to improve SNR.

```bash
./call_coreg_toPDw.sh [--pdw-t1w-only] <INPUT_DIR>
```

**Arguments:**

| Argument    | Description                                                                        |
| ----------- | ---------------------------------------------------------------------------------- |
| `INPUT_DIR` | Path to QSMxT output directory containing Chimaps in `transform_to_orig/` subdirs  |

**Options:**

| Option             | Description                                                                 |
| ------------------ | --------------------------------------------------------------------------- |
| `--pdw-t1w-only`   | Average only PDw and T1w Chimaps. MTw is skipped in averaging.              |

**What it does:**

1. Finds all subjects and sessions in the input directory.
2. Identifies T1w, MTw, and PDw Chimaps in each `transform_to_orig/` subdirectory.
3. Submits SLURM coregistration jobs (`coreg_toPDw_slurm.sh`) to align T1w and MTw Chimaps to PDw space using SPM12 rigid body transformation.
4. Submits a dependent averaging job (`average_chimaps_slurm.sh`):
   - Default mode: runs after both T1w and MTw coregistration jobs complete and averages PDw + T1w + MTw.
   - `--pdw-t1w-only` mode: runs after T1w coregistration only and averages PDw + T1w. Missing MTw does not block averaging.

**Output files** (saved in `<subject>/<session>/anat/coreg_toPDw/`):

| File                                                     | Description                                      |
| -------------------------------------------------------- | ------------------------------------------------ |
| `coreg_<subject>_<session>_acq-T1w_*_MPM_Chimap.nii`    | Coregistered T1w Chimap                          |
| `coreg_<subject>_<session>_acq-MTw_*_MPM_Chimap.nii`    | Coregistered MTw Chimap                          |
| `<subject>_<session>_merged_Chimap.nii`                  | Concatenated 4D volume of included Chimaps       |
| `<subject>_<session>_mean_Chimap.nii`                    | Averaged Chimap (improved SNR)                   |

**Example:**

```bash
./call_coreg_toPDw.sh /path/to/qsmxt_output

# Average only PDw + T1w (skip MTw in averaging)
./call_coreg_toPDw.sh --pdw-t1w-only /path/to/qsmxt_output
```

### Spatial Transformations (Deprecated Standalone Scripts)

These standalone scripts are provided for reference but their functionality is now integrated into the main workflow:

- **`deprecated_transform_to_orig.sh`** — Transforms already-processed QSMxT outputs back to original acquisition space. This functionality is now integrated via the `--transform-to-orig` flag in `call_qsmxt_n.sh`.

  ```bash
  ./deprecated_transform_to_orig.sh <QSMXT_OUTPUT_DIR> <ORIGINAL_INPUT_DIR>
  ```

- **`deprecated_transform_to_mpm.sh`** — Transforms Chimap outputs to co-registered MPM reference space using FSL flirt with spline interpolation.

  ```bash
  ./deprecated_transform_to_mpm.sh <QSMXT_OUTPUT_DIR> <MPM_REFERENCE_DIR>
  ```

> **Note:** The MPM-space transformation using original hMRI toolbox coregistrations turned out to be problematic as the resulting sforms/qforms of T1w and MTw Chimaps differ from the PDw Chimap. The recommended approach is to use `call_coreg_toPDw.sh` instead, which performs a separate rigid-body registration with SPM.

## Typical End-to-End Workflow

```bash
# 1. (Optional) Run brain extraction with SynthStrip
./call_synthstrip.sh --no-csf --holefill 7 <INPUT_DIR> <SYNTHSTRIP_OUTPUT_DIR> sub-001 sub-002

# 2. Run QSMxT (if using SynthStrip masks, edit qsmxt_slurm_n.sh first — see above)
./call_qsmxt_n.sh --transform-to-orig <INPUT_DIR> <OUTPUT_DIR> sub-001 sub-002

# 3. Coregister and average Chimaps
./call_coreg_toPDw.sh [--pdw-t1w-only] <OUTPUT_DIR>
```

## Repository Structure

| File / Directory                  | Description                                                        |
| --------------------------------- | ------------------------------------------------------------------ |
| `call_qsmxt_n.sh`                | Main batch submission script for QSMxT processing                  |
| `qsmxt_slurm_n.sh`               | SLURM job script for a single QSMxT subject/session                |
| `call_synthstrip.sh`             | Batch submission script for SynthStrip brain extraction             |
| `synthstrip_slurm.sh`            | SLURM job script for SynthStrip on a single subject/session        |
| `call_coreg_toPDw.sh`            | Batch submission for Chimap coregistration to PDw space             |
| `coreg_toPDw_slurm.sh`           | SLURM job script for SPM coregistration                            |
| `coreg_toPDw.m`                  | MATLAB/SPM function for rigid body coregistration                  |
| `average_chimaps_slurm.sh`       | SLURM job script for merging and averaging Chimaps                 |
| `deprecated_transform_to_orig.sh`| Standalone script for transform-to-original-space (deprecated)     |
| `deprecated_transform_to_mpm.sh` | Standalone script for transform-to-MPM-space (deprecated)          |
| `sform_toPDw_manTest.py`         | Python utility for sform inspection/testing                        |
| `qsm_weighted_av_*.m`            | MATLAB scripts for weighted averaging of QSM maps                  |
| `logs/`                          | Directory for SLURM job output logs                                |
| `deprecated_qsmxt/`              | Older versions of QSMxT scripts                                   |

## License

See [LICENSE](LICENSE) for details.
