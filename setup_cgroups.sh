#!/bin/bash
# setup_cgroups.sh
# Create 7 cgroups named mig0..mig6 using cgroup v2 (direct /sys/fs/cgroup manipulation).
# Falls back to cgroup v1 `cgcreate` only if cgroup v2 isn't available.

set -euo pipefail

CG_PREFIX="mig"
NUM=7
CORES_PER=10
TOTAL_CORES=72

CG_ROOT="/sys/fs/cgroup"

echo "Preparing to create ${NUM} cgroups (prefers cgroup v2 under ${CG_ROOT})"

# Basic checks
if [ ! -d "${CG_ROOT}" ]; then
  echo "ERROR: ${CG_ROOT} does not exist. Are cgroups mounted?"
  exit 1
fi

USE_CG_V2=0
if [ -f "${CG_ROOT}/cgroup.controllers" ]; then
  USE_CG_V2=1
fi

if [ "$((NUM * CORES_PER))" -gt "$TOTAL_CORES" ]; then
  echo "ERROR: Not enough CPU cores for ${NUM} groups of ${CORES_PER} cores (have ${TOTAL_CORES})."
  exit 1
fi

if [ "$USE_CG_V2" -eq 1 ]; then
  controllers=$(cat ${CG_ROOT}/cgroup.controllers)
  echo "cgroup v2 detected. Available controllers: ${controllers}"
  if echo "$controllers" | grep -qw cpuset; then
    HAVE_CPUSET=1
  else
    HAVE_CPUSET=0
  fi
else
  HAVE_CPUSET=0
fi

if [ "$USE_CG_V2" -ne 1 ] && command -v cgcreate >/dev/null 2>&1; then
  echo "cgroup v2 not available; falling back to cgroup v1 tools (cgcreate)."
  USE_CGCREATE=1
else
  USE_CGCREATE=0
fi

for i in $(seq 0 $((NUM-1))); do
  name="${CG_PREFIX}${i}"
  start_core=$((i * CORES_PER))
  end_core=$((start_core + CORES_PER - 1))

  if [ "$USE_CG_V2" -eq 1 ]; then
    cgdir="${CG_ROOT}/${name}"
    echo "Creating cgroup v2 directory: ${cgdir} (cores ${start_core}-${end_core})"
    sudo mkdir -p "${cgdir}"

    # If cpuset controller is available, enable it for the child and set cpus/mems
    if [ "$HAVE_CPUSET" -eq 1 ]; then
      # Enable cpuset in this cgroup so cpuset.* files appear
      # write +cpuset into subtree_control of this cgroup's parent if possible
      parent="$(dirname "${cgdir}")"
      # Enable controller on the parent so child can use it (best-effort)
      if [ -f "${parent}/cgroup.subtree_control" ]; then
        sudo bash -c "echo +cpuset > '${parent}/cgroup.subtree_control'" || true
      fi

      # Set cpuset.mems then cpuset.cpus (cpuset requires mems before cpus)
      if [ -f "${cgdir}/cpuset.mems" ]; then
        sudo bash -c "echo 0 > '${cgdir}/cpuset.mems'" || true
      fi
      if [ -f "${cgdir}/cpuset.cpus" ]; then
        sudo bash -c "echo ${start_core}-${end_core} > '${cgdir}/cpuset.cpus'" || true
      else
        echo "WARNING: ${cgdir}/cpuset.cpus not available; cpuset controller may not be enabled." >&2
      fi
    else
      echo "WARNING: cpuset controller not available in cgroup v2; cannot set CPU affinity per cgroup." >&2
      echo "You may still restrict CPU usage with cpu.max or use system-level tooling." >&2
    fi

  elif [ "$USE_CGCREATE" -eq 1 ]; then
    echo "Creating cgroup v1: ${name} (cores ${start_core}-${end_core})"
    sudo cgcreate -g cpu:/${name} || true
    sudo cgset -r cpu.cpus=${start_core}-${end_core} ${name}
  else
    echo "ERROR: No method available to create cgroups (no cgroup v2 and no cgcreate)." >&2
    exit 1
  fi
done

if [ "$USE_CG_V2" -eq 1 ]; then
  echo "Done. Created ${NUM} cgroups under ${CG_ROOT}/${CG_PREFIX}0..${CG_PREFIX}$((NUM-1))."
  echo "To run a command inside a cgroup (v2), start the command and then write its PID into the cgroup's cgroup.procs."
  echo "Example:"
  echo "  ./your_command &"
  echo "  echo \$! | sudo tee /sys/fs/cgroup/mig2/cgroup.procs"
  echo "Or use the helper wrapper 'run_on_mig.sh' which will place the process into the proper cgroup."
else
  echo "Done. Created ${NUM} cgroups (v1). Run commands with: cgexec -g cpu:/migX <command>"
fi

# End of script
