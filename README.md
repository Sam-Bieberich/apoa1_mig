# APOA1 on MIG (cgroup v2 only)

This repo runs the APOA1 NAMD job on a single MIG slice with CPU pinning via cgroup v2. No cgcreate/cgexec/systemd slices are used.

## Files
- `7_mig.sh` — creates 7 MIG partitions (mig0..mig6).
- `setup_cgroups.sh` — makes `/sys/fs/cgroup/mig0..mig6`, assigns 10 CPU cores each (0-69) when `cpuset` is available.
- `run_on_mig.sh` — wrapper that sets `CUDA_VISIBLE_DEVICES` to the MIG UUID, launches a command, writes its PID into `/sys/fs/cgroup/migX/cgroup.procs`, and supports `-o/--out` for log capture.
- `run_namd_gpu.sh` — provided SLURM-driven launcher (unchanged).
- `runjob` — provided sbatch script (unchanged).
- `apao1.namd` — NAMD input (other deps are expected in this directory).

## Prerequisites
- cgroup v2 mounted at `/sys/fs/cgroup` with `cpuset` controller available for CPU pinning; if `cpuset` is missing, CPU pinning is skipped but cgroups are still created.
- sudo rights to write PIDs into `/sys/fs/cgroup/migX/cgroup.procs`.
- NVIDIA drivers with MIG enabled; `nvidia-smi -L` should list MIG devices.
- NAMD (e.g., `namd3`) available, or the provided `run_namd_gpu.sh` via module loads.

## Setup
1) Create MIG slices
```bash
sudo bash 7_mig.sh
```
2) Create CPU cgroups (mig0..mig6, 10 cores each)
```bash
sudo bash setup_cgroups.sh
```

## Run directly (example: mig2, log to file)
```bash
./run_on_mig.sh 2 -o /scratch/11098/sambieberich/APOP1/apao1-mig.log -- namd3 +p10 /scratch/11098/sambieberich/APOP1/apao1.namd
tail -f apao1-mig.log
```
- `-o` captures stdout/stderr to `apao1-mig.log`.
- The process PID is placed into `/sys/fs/cgroup/mig2/cgroup.procs`.
- `CUDA_VISIBLE_DEVICES` is set to the MIG UUID so `+devices 0` maps to that slice.

## Use the provided SLURM launchers (unchanged)
- Inside an interactive SLURM allocation on the target node:
```bash
module load cuda/12.6 nvmath/12.6.0 openmpi/5.0.5 ucx/1.18.0 namd-gpu/3.0.2
./run_on_mig.sh 2 -o apao1-mig.log -- run_namd_gpu apao1.namd apao1-run.out
```
- If submitting a batch job while keeping `runjob` untouched:
```bash
sbatch --wrap="./run_on_mig.sh 2 -o /scratch/11098/sambieberich/APOP1/apao1-mig.log -- run_namd_gpu apao1.namd apao1-run.out" runjob
```
  The wrapper runs inside the sbatch step and moves the NAMD PID into `/sys/fs/cgroup/mig2`.
- `run_namd_gpu.sh` uses `srun ... +devices 0`; with `run_on_mig.sh` setting `CUDA_VISIBLE_DEVICES`, device 0 is the selected MIG slice.

## Notes & tips
- Run as your normal user (do not wrap the whole script with sudo); it will prompt for sudo only when writing to cgroup/log if needed. Running as root can fail to write logs on root-squashed filesystems and may miss your module environment.
- If asked for a password, it is to write into `/sys/fs/cgroup/migX/cgroup.procs`.
- If `cpuset` is unavailable in cgroup v2, CPU pinning is skipped; GPU isolation via MIG still applies.
- Tail logs while running: `tail -f apao1-mig.log`.
