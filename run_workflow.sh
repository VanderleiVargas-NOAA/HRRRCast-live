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
BATCH_SIZE=${BATCH_SIZE:-0}                # cycles to submit before WAITING for them
                                           # to finish; 0 = submit all at once (no wait)
POLL_INTERVAL=${POLL_INTERVAL:-60}         # seconds between queue checks while waiting
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
# submit_all.sh runs on stderr (its set -x trace + summary is shown live); the
# submitted SLURM job ids are echoed on stdout so the caller can collect them.
launch_cycle() {
    local init_time=$1
    echo "[submit] $init_time" >&2
    local out
    out=$("$SUBMIT_SCRIPT" "$init_time" "$FCST_LENGTH" "$N_ENSEMBLES" "$N_GPUS")
    printf '%s\n' "$out" >&2                     # show submit_all's summary lines
    awk '/^Submitted/ {print $NF}' <<<"$out"     # emit the job ids (last field)
}

# Block until every job id in the comma-separated list has left the queue.
wait_for_jobs() {
    local ids="$1"
    [[ -z "$ids" ]] && return 0
    echo "[batch] waiting for jobs to finish: ${ids}" >&2
    while :; do
        local n
        n=$(squeue -h -j "$ids" -o '%i' 2>/dev/null | wc -l || true)
        (( n == 0 )) && break
        echo "[batch] $n job(s)/array-task(s) still queued or running; checking again in ${POLL_INTERVAL}s" >&2
        sleep "$POLL_INTERVAL"
    done
    echo "[batch] all jobs finished." >&2
}

if (( BATCH_SIZE > 0 )); then
    total=${#CYCLES[@]}; b=0
    for (( i=0; i<total; i+=BATCH_SIZE )); do
        b=$(( b + 1 ))
        batch=( "${CYCLES[@]:i:BATCH_SIZE}" )
        echo "=== batch ${b}: ${batch[*]} ==="
        ids=""
        for cyc in "${batch[@]}"; do
            cyc_ids=$(launch_cycle "$cyc" | paste -sd, -)
            [[ -n "$cyc_ids" ]] && ids+="${ids:+,}${cyc_ids}"
        done
        wait_for_jobs "$ids"
    done
else
    for cyc in "${CYCLES[@]}"; do
        launch_cycle "$cyc" >/dev/null      # ids not needed when not batching
    done
fi
echo "All forecast pipelines submitted."
echo "Done."

