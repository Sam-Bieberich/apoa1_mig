#!/bin/bash
# setup_cgroups.sh
# Creates 7 cgroups named mig0..mig6 and restricts each to 10 CPU cores.

set -euo pipefail

CG_PREFIX="mig"
NUM=7
CORES_PER=10
TOTAL_CORES=72

if ! command -v cgcreate >/dev/null 2>&1; then
  echo "ERROR: 'cgcreate' not found. Install 'cgroup-tools' (Ubuntu: apt install cgroup-tools) or create cgroups with your distro's method."
  exit 1
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

  echo "Creating cgroup: ${name} (cores ${start_core}-${end_core})"
  sudo cgcreate -g cpu:/${name} || true
  sudo cgset -r cpu.cpus=${start_core}-${end_core} ${name}
  # Optionally set cpu.shares or other limits here
done

echo "Done. Created ${NUM} cgroups (${CG_PREFIX}0..${CG_PREFIX}$((NUM-1)))."

echo "To run a command in a cgroup, use: cgexec -g cpu:/migX <command>"

# End of script
