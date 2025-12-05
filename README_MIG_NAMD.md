README — Running NAMD on a single MIG partition

Purpose
- Minimal instructions to create cgroups, bind a MIG partition, and run NAMD (or any command) on that partition with 10 CPU cores assigned.

Files added
- `setup_cgroups.sh` — creates 7 cgroups `mig0`..`mig6`, each set to 10 CPU cores (0-69). Requires `sudo` and `cgcreate`/`cgset`.
- `run_on_mig.sh` — wrapper to run an arbitrary command in a chosen cgroup and bind CUDA to a MIG device by index or UUID.

Quick start
1. Create MIG partitions (use your existing script):

```bash
sudo bash 7_mig.sh
```

2. Create CPU cgroups (assign 10 cores each):

```bash
cd data_for_ref
sudo bash setup_cgroups.sh
```

3. Run NAMD on MIG partition index 2 (example):

```bash
cd data_for_ref
./run_on_mig.sh 2 -- namd2 +p10 myconf.conf
```

Notes & troubleshooting
- `setup_cgroups.sh` uses `cgcreate`/`cgset` (cgroup v1 toolchain). If your system uses cgroup v2 or systemd slices, create equivalent slices and assign CPUAffinity.
- `run_on_mig.sh` expects `nvidia-smi` to list MIG devices. You can also pass a MIG UUID directly, e.g. `UUID:MIG-GPU-xxxx`.
- Make the scripts executable: `chmod +x setup_cgroups.sh run_on_mig.sh run_namd_mig.sh`.

If you want, I can update `run_namd_mig.sh` to call `run_on_mig.sh` with a NAMD-specific wrapper.
