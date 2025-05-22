# run_qsmxt
A repository to QSMxT for a batch of subject/sessions


## How to run 

- adjust input and output paths, logs path and possibly other properties in `qsmxt_slurm.sh`

```
getserver -sb

cd /path/to/output/dir
# before the qsmxt command is executed, the singularity container is made available by sourcing `bash.singularity` (custom file) and the correct conda environment is activated after sourcing `bash.preferences` (custom file)

/data/u_kuegler_software/git/qsm/run_qsmxt/call_qsmxt.sh sub-001 sub-002 sub-003
```

> Note: it is important to specify the session's name, not only the subject's name. Otherwise, the execution of `call_qsmxt.sh` raises an error in the romeo_combine_phase step *(not sure why this happens)*.

> Note: These scripts are proprietary, as they require some custom files for making the singularity container and conda available
