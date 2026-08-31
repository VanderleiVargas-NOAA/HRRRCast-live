#!/bin/bash
#SBATCH --job-name=finalize
#SBATCH --output=logs/finalize_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[FINALIZE_WALLTIME]

# Flip this init from 0 to 1 in the status ledger. This job is submitted with
# an afterok dependency on EVERY pipeline job, so SLURM only lets it run when all
# of them succeeded. If anything failed, the dependency is unsatisfiable and this
# job is cancelled (never runs) -> the ledger stays 0 = not completed.

# set vars
INIT_TIME="@[INIT_TIME]"
DATAROOT=@[DATAROOT]

# cycle stamp YYYYMMDDHH
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"

LEDGER="${DATAROOT}/logs/run_status.tsv"

# ledger_set <init_stamp> <status> [detail] — atomic upsert keyed by init.
# flock serializes concurrent cycles; per-pid temp + rename keeps it consistent.
ledger_set() {
    local init="$1" status="$2" detail="${3:-}"
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$(dirname "$LEDGER")"
    (
        flock -x 200
        touch "$LEDGER"
        awk -F'\t' -v k="$init" '$1!=k' "$LEDGER" > "${LEDGER}.$$" 2>/dev/null || true
        printf '%s\t%s\t%s\t%s\n' "$init" "$status" "$ts" "$detail" >> "${LEDGER}.$$"
        mv "${LEDGER}.$$" "$LEDGER"
    ) 200>"${LEDGER}.lock"
}

echo "All pipeline jobs succeeded — marking ${INIT_STAMP} = 1 (completed)."
ledger_set "$INIT_STAMP" 1 "completed"
echo "Done finalize for ${INIT_STAMP}"
