#!/usr/bin/env bash
# run_workflow.sh — driver for live HRRRCast forecasts
#
# Owns only the run window and cadence. It generates the list of init cycles
# and launches the HRRRCast pipeline once per cycle (sequentially).
# All HRRRCast-specific parameters (ensembles, GPUs, plotting, roots, env)
# are set inside the HRRRCast scripts, not here.
#
# Usage:
#   ./run_workflow.sh
#   START_DATE=2024-07-17T00 END_DATE=2024-07-18T00 INIT_INTERVAL=6 FCST_LENGTH=24 ./run_workflow.sh
#
#   # Rerun ONLY the cycles listed in a file (one INIT_TIME per line, e.g. the
#   # failed_runs.txt written by job-check.sh). Overrides the date range.
#   ./run_workflow.sh failed_runs.txt
#   RERUN_FILE=failed_runs.txt ./run_workflow.sh
#
#   # Toggle individual jobs (passed through to submit_all.sh), e.g.
#   RUN_GENENSPROD=YES RUN_GRIDSTAT=YES ./run_workflow.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Main parameters (override via environment)
# ---------------------------------------------------------------------------
START_DATE=${START_DATE:-"2026-05-31T18"}  # first init cycle (YYYY-MM-DDTHH)
END_DATE=${END_DATE:-"2026-05-31T18"}      # last init cycle  (YYYY-MM-DDTHH, inclusive)
INIT_INTERVAL=${INIT_INTERVAL:-6}          # hours between init cycles
FCST_LENGTH=${FCST_LENGTH:-24}             # forecast length (hours)
N_ENSEMBLES=${N_ENSEMBLES:-10}             # ensemble members
N_GPUS=${N_GPUS:-2}                        # GPU slots (forecast job-array width)
# NOTE: cycles are submitted sequentially, NOT in parallel. submit_all.sh only
# *submits* the SLURM jobs (fast); the real parallel work runs in SLURM via the
# dependency chain. Running submit_all.sh concurrently is unsafe because it
# regenerates its job scripts into a single shared path ($DATAROOT/logs/job-*.sh),
# so concurrent cycles clobber each other and all submit the same INIT_TIME.

# SLURM accounts (exported to the HRRRCast pipeline)
ACCNR=${ACCNR:-gpu-ai4wp}                   # GPU account
CPU_ACCNR=${CPU_ACCNR:-fv3lam}              # CPU account
export ACCNR CPU_ACCNR

# HRRRCast entry point
SUBMIT_SCRIPT=${SUBMIT_SCRIPT:-"$(cd "$(dirname "$0")" && pwd)/submit_all.sh"}

# Optional rerun file (env var or first CLI argument). If set, cycles are read
# from it instead of being generated from the date range.
RERUN_FILE=${RERUN_FILE:-${1:-}}

# ---------------------------------------------------------------------------
# Build the list of init cycles: either from a rerun file, or from the date range
# ---------------------------------------------------------------------------
CYCLES=()
if [[ -n "$RERUN_FILE" ]]; then
    [[ -f "$RERUN_FILE" ]] || { echo "ERROR: rerun file not found: $RERUN_FILE" >&2; exit 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"                            # strip trailing comments
        line="${line//[[:space:]]/}"                  # strip all whitespace
        [[ -n "$line" ]] && CYCLES+=( "$line" )
    done < "$RERUN_FILE"
    (( ${#CYCLES[@]} > 0 )) || { echo "No cycles found in $RERUN_FILE — nothing to do."; exit 0; }
    SOURCE_DESC="rerun file: $RERUN_FILE"
else
    # GNU date on Linux; on macOS install coreutils and use `gdate`.
    DATE_BIN=${DATE_BIN:-date}
    start_epoch=$($DATE_BIN -u -d "${START_DATE//T/ }:00:00 UTC" +%s)
    end_epoch=$($DATE_BIN -u -d "${END_DATE//T/ }:00:00 UTC" +%s)

    if (( end_epoch < start_epoch )); then
        echo "ERROR: END_DATE ($END_DATE) is before START_DATE ($START_DATE)." >&2
        exit 1
    fi

    epoch=$start_epoch
    while (( epoch <= end_epoch )); do
        CYCLES+=( "$($DATE_BIN -u -d "@$epoch" +%Y-%m-%dT%H)" )
        epoch=$(( epoch + INIT_INTERVAL * 3600 ))
    done
    SOURCE_DESC="range ${START_DATE}..${END_DATE} step ${INIT_INTERVAL}h"
fi

# ---------------------------------------------------------------------------
echo "=== HRRRCast live driver ==="
echo "SOURCE        : $SOURCE_DESC"
echo "FCST_LENGTH   : ${FCST_LENGTH}h"
echo "N_ENSEMBLES   : $N_ENSEMBLES"
echo "N_GPUS        : $N_GPUS"
echo "ACCNR         : $ACCNR"
echo "CPU_ACCNR     : $CPU_ACCNR"
echo "N_CYCLES      : ${#CYCLES[@]}  (${CYCLES[*]})"
echo "SUBMIT_SCRIPT : $SUBMIT_SCRIPT"
echo "==========================="

# --- Launch the HRRRCast pipeline per cycle (sequentially) -----------------
# Per cycle:
#   ACCNR=.. CPU_ACCNR=.. submit_all.sh <INIT_TIME> <FCST_LENGTH> <N_ENSEMBLES> <N_GPUS>
launch_cycle() {
    local init_time=$1
    echo "[submit] $init_time"
    "$SUBMIT_SCRIPT" "$init_time" "$FCST_LENGTH" "$N_ENSEMBLES" "$N_GPUS"
}

for cyc in "${CYCLES[@]}"; do
    launch_cycle "$cyc"
done
echo "All forecast pipelines submitted."
echo "Done."
