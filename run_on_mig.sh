#!/bin/bash
# run_on_mig.sh
# Wrapper to run an arbitrary command on a specific MIG partition + cgroup.
# Usage: ./run_on_mig.sh <mig_index_or_uuid> -- <command...>
# Examples:
#  ./run_on_mig.sh 2 -- ./namd2 +p10 myconf.conf
#  ./run_on_mig.sh UUID:MIG-GPU-xxxx-xxxxx -- ./my_script.sh

set -euo pipefail

if [ "$#" -lt 3 ]; then
  cat <<EOF
Usage: $0 <mig_index_or_uuid> -- <command...>
Examples:
  $0 2 -- namd2 +p10 myconf.conf
  $0 UUID:MIG-GPU-xxxxx -- ./run_my_job.sh
EOF
  exit 1
fi

TARGET=$1
shift
if [ "$1" != "--" ]; then
  echo "ERROR: missing '--' separator before command"
  exit 1
fi
shift
CMD=("$@")

# Determine cgroup name from index or UUID naming
# If TARGET starts with UUID:, treat remainder as the MIG UUID
if [[ "$TARGET" == UUID:* ]]; then
  MIG_UUID=${TARGET#UUID:}
else
  # Try to find the N-th MIG partition listed by nvidia-smi
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "ERROR: nvidia-smi not found. Ensure NVIDIA drivers are installed."
    exit 1
  fi

  # Collect lines that describe MIG devices
  mapfile -t mig_lines < <(nvidia-smi -L | grep -i "MIG" || true)
  if [ ${#mig_lines[@]} -eq 0 ]; then
    echo "ERROR: No MIG devices found in 'nvidia-smi -L'"
    exit 1
  fi

  # If TARGET is numeric, pick that indexed line (0-based)
  if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    idx=$TARGET
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#mig_lines[@]}" ]; then
      echo "ERROR: MIG index ${idx} out of range (found ${#mig_lines[@]} MIG devices)"
      exit 1
    fi
    line="${mig_lines[$idx]}"
    # Expect the UUID to be last token like (UUID: MIG-xxx)
    MIG_UUID=$(echo "$line" | awk '{print $NF}' | tr -d '()')
  else
    echo "ERROR: TARGET must be numeric index (0..N) or UUID:<id>"
    exit 1
  fi
fi

if [ -z "${MIG_UUID:-}" ]; then
  echo "ERROR: unable to determine MIG UUID"
  exit 1
fi

# Prepare cgroup name based on common convention mig<index> if numeric target was used
CGROUP=""
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  CGROUP="mig${TARGET}"
else
  # If provided UUID form, user must also provide a cgroup name (fallback)
  # We'll try to infer a free cgroup by searching existing migN cgroups.
  for i in {0..6}; do
    if cgget -r cpu.cpus mig${i} >/dev/null 2>&1; then
      CGROUP="mig${i}"
      break
    fi
  done
  if [ -z "$CGROUP" ]; then
    echo "WARNING: could not infer cgroup; defaulting to 'mig0'"
    CGROUP="mig0"
  fi
fi

# Check cgexec availability
if ! command -v cgexec >/dev/null 2>&1; then
  echo "ERROR: 'cgexec' not found. Install 'cgroup-tools' or run the command manually with taskset/cgroups." 
  exit 1
fi

# Export CUDA_VISIBLE_DEVICES to the MIG UUID so CUDA apps use the partition
export CUDA_VISIBLE_DEVICES="$MIG_UUID"

echo "Running command in cgroup: ${CGROUP} using MIG UUID: ${MIG_UUID}"

echo "Command: ${CMD[*]}"

# Run the command inside the cpu cgroup
exec cgexec -g cpu:/${CGROUP} "${CMD[@]}"

# End of script
