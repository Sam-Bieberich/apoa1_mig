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
Usage: $0 <mig_index_or_uuid> [-o OUTPUT] -- <command...>
Examples:
  $0 2 -- namd2 +p10 myconf.conf
  $0 2 -o namd.out -- namd2 +p10 myconf.conf
  $0 UUID:MIG-GPU-xxxxx -- ./run_my_job.sh
EOF
  exit 1
fi

TARGET=$1
shift

OUTPUT_FILE=""

# Parse optional flags before the -- separator
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
  case "$1" in
    -o|--out|--output)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --out requires a file argument"
        exit 1
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown option '$1' before --"
      exit 1
      ;;
  esac
done

if [ "$#" -lt 2 ] || [ "$1" != "--" ]; then
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
  # If provided UUID form, try to find an existing migN cgroup directory under cgroup v2
  for i in {0..6}; do
    if [ -d "/sys/fs/cgroup/mig${i}" ]; then
      CGROUP="mig${i}"
      break
    fi
  done
  if [ -z "$CGROUP" ]; then
    echo "WARNING: could not infer cgroup; defaulting to 'mig0'"
    CGROUP="mig0"
  fi
fi

# Prefer cgroup v2. If present, place the launched process into /sys/fs/cgroup/<CGROUP>/cgroup.procs
CG_ROOT="/sys/fs/cgroup"
USE_CG_V2=0
if [ -f "${CG_ROOT}/cgroup.controllers" ]; then
  USE_CG_V2=1
fi

if [ "$USE_CG_V2" -ne 1 ]; then
  echo "ERROR: cgroup v2 not detected at ${CG_ROOT}. This script expects cgroup v2 on Ubuntu." >&2
  exit 1
fi

# Ensure the target cgroup directory exists
CGDIR="${CG_ROOT}/${CGROUP}"
if [ ! -d "$CGDIR" ]; then
  echo "cgroup v2 directory $CGDIR not found — attempting to create it (requires sudo)"
  sudo mkdir -p "$CGDIR"
fi

# Export CUDA_VISIBLE_DEVICES to the MIG UUID so CUDA apps use the partition
export CUDA_VISIBLE_DEVICES="$MIG_UUID"

echo "Running command in cgroup v2: ${CGDIR} using MIG UUID: ${MIG_UUID}"
if [ -n "$OUTPUT_FILE" ]; then
  echo "Output file: ${OUTPUT_FILE}"
fi
echo "Command: ${CMD[*]}"

# Move this shell into the cgroup first so the launched command inherits it
if ! echo "$$" | sudo tee "${CGDIR}/cgroup.procs" >/dev/null; then
  echo "ERROR: failed to place shell PID $$ into ${CGDIR}/cgroup.procs" >&2
  exit 1
fi

# Run the command (inherits cgroup from this shell)
if [ -n "$OUTPUT_FILE" ]; then
  # If output file not writable, fall back to sudo tee
  if [ -w "$OUTPUT_FILE" ] || { touch "$OUTPUT_FILE" 2>/dev/null && [ -w "$OUTPUT_FILE" ]; }; then
    "${CMD[@]}" 2>&1 | tee "$OUTPUT_FILE"
    exit_code=${PIPESTATUS[0]}
  else
    echo "Output file not writable, using sudo tee: $OUTPUT_FILE"
    "${CMD[@]}" 2>&1 | sudo tee "$OUTPUT_FILE"
    exit_code=${PIPESTATUS[0]}
  fi
else
  "${CMD[@]}"
  exit_code=$?
fi

exit $exit_code

# End of script
