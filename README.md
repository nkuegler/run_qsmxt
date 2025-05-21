# run_qsmxt
A repository to QSMxT for a batch of subject/sessions


## How to run 

- adjust input and output paths, logs path and possibly other properties in `qsmxt_slurm.sh`

```
getserver -sb

cd /path/to/output/dir
sing 
conda activate qsmxt8

/data/u_kuegler_software/git/qsm/run_qsmxt/call_qsmxt.sh sub-001 sub-002 sub-003
```

