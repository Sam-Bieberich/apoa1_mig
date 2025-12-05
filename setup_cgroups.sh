#!/bin/bash
# setup_cgroups.sh
# Creates 7 cgroups named mig0..mig6 and restricts each to 10 CPU cores.

set -euo pipefail

CG_PREFIX="mig"
NUM=7
CORES_PER=10
TOTAL_CORES=72

USE_CGCREATE=0
if command -v cgcreate >/dev/null 2>&1; then
  USE_CGCREATE=1
fi

# If cgcreate isn't available, fall back to systemd slices (Ubuntu default cgroup v2)
if [ "$USE_CGCREATE" -eq 0 ]; then
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "ERROR: neither 'cgcreate' nor 'systemctl' found. Install 'cgroup-tools' or use systemd on Ubuntu."
    exit 1
  fi
  echo "'cgcreate' not found — will create systemd slices (Ubuntu default / cgroup v2)"
fi

# Validate total cores enough
if [ $((NUM * CORES_PER)) -gt "$TOTAL_CORES" ]; then
  echo "ERROR: Not enough CPU cores for ${NUM} groups of ${CORES_PER} cores (have ${TOTAL_CORES})."
  exit 1
fi

for i in $(seq 0 $((NUM-1))); do
  name="${CG_PREFIX}${i}"
  start_core=$((i * CORES_PER))
  end_core=$((start_core + CORES_PER - 1))

  if [ "$USE_CGCREATE" -eq 1 ]; then
    echo "Creating cgroup (v1) : ${name} (cores ${start_core}-${end_core})"
    sudo cgcreate -g cpu:/${name} || true
    sudo cgset -r cpu.cpus=${start_core}-${end_core} ${name}
  else
    slice_name="${name}.slice"
    echo "Creating systemd slice: ${slice_name} (CPUAffinity=${start_core}-${end_core})"
    # Create/modify the transient slice and set CPUAffinity. This uses runtime properties
    # and will survive until reboot. For persistent slices, drop-in files can be created.
    sudo systemctl set-property ${slice_name} CPUAffinity=${start_core}-${end_core} || true
  fi
done

if [ "$USE_CGCREATE" -eq 1 ]; then
  echo "Done. Created ${NUM} cgroups (${CG_PREFIX}0..${CG_PREFIX}$((NUM-1)))."
  echo "Run a command in a cgroup: cgexec -g cpu:/migX <command>"
else
  echo "Done. Created ${NUM} systemd slices (${CG_PREFIX}0.slice..${CG_PREFIX}$((NUM-1)).slice)."
  echo "Run a command in a slice (example for NAMD):"
  echo "  sudo systemd-run --slice=mig2.slice --unit=namd_mig2 --scope namd2 +p10 myconf.conf"
  echo "Or run any command in a slice with:"
  echo "  sudo systemd-run --slice=migX.slice --unit=<name> --scope <command...>"
  echo "You can also create persistent unit files that set 'Slice=migX.slice' in their service unit."
fi

# End of script
