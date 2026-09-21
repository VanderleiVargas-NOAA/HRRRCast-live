#!/usr/bin/env bash
# auto_rerun.sh — cron-driven auto-resubmit of failed HRRRCast cycles.
#
# Logic (matches the run_status.tsv ledger: 0 = started/failed, 1 = completed):
#   1. If a previous instance is still running -> exit (flock).
#   2. If ANY SLURM job is queued/running for the user (optionally filtered by
#      job name) -> the pipeline is still working, exit and do nothing.
#   3. Queue is idle, so every ledger row still at 0 is a genuine FAILURE:
#        - none failed        -> write a completion flag + summary, exit.
#        - some failed         -> resubmit them via run_workflow.sh, but skip any
#                                 init that has already been retried MAX_ATTEMPTS
#                                 times (logged to a give-up file).
#
# Cron example (every 30 min):
#   */30 * * * * /path/to/HRRRCast-live/auto_rerun.sh >> /path/to/HRRRCast-live/logs/autorerun/cron.out 2>&1
# NOTE: cron has a minimal environment. Make sure sbatch/squeue are on PATH and
# any needed modules are loaded — set ENV_SETUP below if so.

set -euo pipefail

# --------------------------------------------------------------------------
# Configuration (override via environment)
# --------------------------------------------------------------------------
ROOT=${ROOT:-"$(cd "$(dirname "$0")" && pwd)"}   # repo / DATAROOT (holds logs/run_status.tsv)
LEDGER=${LEDGER:-"$ROOT/logs/run_status.tsv"}
STATE_DIR=${STATE_DIR:-"$ROOT/logs/autorerun"}
RUN_WORKFLOW=${RUN_WORKFLOW:-"$ROOT/run_workflow.sh"}

# Pipeline parameters — MUST match how you normally launch the run.
export N_ENSEMBLES=${N_ENSEMBLES:-18}
export FCST_LENGTH=${FCST_LENGTH:-24}
export N_GPUS=${N_GPUS:-2}
export BATCH_SIZE=${BATCH_SIZE:-4000000}              # stay under QOS limits on big reruns
export ACCNR=${ACCNR:-gpu-ai4wp}
export CPU_ACCNR=${CPU_ACCNR:-fv3lam}

MAX_ATTEMPTS=${MAX_ATTEMPTS:-3}                  # give up on an init after this many auto-retries
USER_NAME=${USER_NAME:-${USER:-$(whoami)}}
JOB_NAME_FILTER=${JOB_NAME_FILTER:-}            # optional: comma list of job names to count
                                                # (empty = count ALL of the user's jobs)
CLEAN_BEFORE_RERUN=${CLEAN_BEFORE_RERUN:-YES}   # remove skip-guarded GenEnsProd output first
DRY_RUN=${DRY_RUN:-NO}                           # YES = show what would happen, submit nothing

# Environment setup for cron (bare env: no conda, maybe no SLURM on PATH).
# Easiest: set CONDA_BASE to `conda info --base` and we activate the hrrrcast env.
# For anything more (module loads, PATH), set ENV_SETUP directly instead.
# hrrrcast is a PREFIX env outside the base's envs/ dir, so activate it by full
# path — activating by name only works when ~/.condarc's envs_dirs is loaded,
# which cron's bare environment does not do.
CONDA_BASE=${CONDA_BASE:-/scratch4/BMC/fv3lam/Vanderlei.Vargas/Models/ufs-srweather-app/conda}
CONDA_ENV=${CONDA_ENV:-/scratch4/BMC/fv3lam/Vanderlei.Vargas/conda/envs/hrrrcast}

# cron's bare env doesn't have SLURM on PATH (squeue/sbatch). Prepend the SLURM
# bin dir here. Find it in your login shell with: dirname $(which squeue)
SLURM_BIN=${SLURM_BIN:-/usr/local/slurm/default/bin}
ENV_SETUP=${ENV_SETUP:-}
if [[ -z "$ENV_SETUP" && -n "$CONDA_BASE" ]]; then
    ENV_SETUP="source $CONDA_BASE/etc/profile.d/conda.sh; conda activate $CONDA_ENV"
fi

# --------------------------------------------------------------------------
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/autorerun.log"
LOCK="$STATE_DIR/autorerun.lock"
DONE_FLAG="$STATE_DIR/all_complete.flag"
ATTEMPTS="$STATE_DIR/attempts.tsv"              # init<TAB>count
GIVEUP="$STATE_DIR/giveup.txt"                  # inits that hit MAX_ATTEMPTS
RERUN_FILE="$STATE_DIR/failed_runs.txt"
STATUS_LATEST="$STATE_DIR/status_latest.txt"    # overwritten each tick: the most recent outcome
STATUS_HISTORY="$STATE_DIR/status_history.tsv"  # appended each tick: time<TAB>state<TAB>detail

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

# record_status <STATE> <detail...> — write a one-line history row + overwrite the
# latest-status file, and echo to the log. STATE is one of:
#   BUSY | ALL_COMPLETE | RESUBMITTED | CAPPED | DRY_RUN | NO_LEDGER
record_status() {
    local state="$1"; shift
    local detail="$*"
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\t%s\t%s\n' "$ts" "$state" "$detail" >> "$STATUS_HISTORY"
    printf 'time:   %s\nstate:  %s\ndetail: %s\n' "$ts" "$state" "$detail" > "$STATUS_LATEST"
    log "[$state] $detail"
}

[[ -n "$ENV_SETUP" ]] && eval "$ENV_SETUP"
[[ -n "$SLURM_BIN" ]] && export PATH="$SLURM_BIN:$PATH"

# stamp (YYYYMMDDHH) -> INIT_TIME (YYYY-MM-DDTHH) that run_workflow.sh expects
stamp_to_init() { sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})$/\1-\2-\3T\4/'; }

# --------------------------------------------------------------------------
# 1. Single-instance lock (non-blocking).
# --------------------------------------------------------------------------
exec 9>"$LOCK"
if ! flock -n 9; then
    log "another auto_rerun is running; exiting."
    exit 0
fi

# --------------------------------------------------------------------------
# 2. Bail out if the pipeline is still working (any queued/running jobs).
# --------------------------------------------------------------------------
# FAIL SAFE: if the queue can't be queried, assume busy and do nothing — never
# resubmit blind (that would duplicate running jobs).
if ! command -v squeue >/dev/null 2>&1; then
    record_status BUSY "squeue not found in PATH — cannot verify the queue; skipping (set ENV_SETUP for cron)."
    exit 0
fi

set +e
q_out=$(squeue -h -u "$USER_NAME" ${JOB_NAME_FILTER:+--name="$JOB_NAME_FILTER"} -o '%i' 2>/dev/null)
q_rc=$?
set -e
if (( q_rc != 0 )); then
    record_status BUSY "squeue exited $q_rc — cannot verify the queue; skipping."
    exit 0
fi

# count non-blank lines (job ids / array tasks); no pipe -> no pipefail surprises
running=$(printf '%s\n' "$q_out" | grep -c '[^[:space:]]' || true)
running=${running:-0}
if (( running > 0 )); then
    record_status BUSY "$running job(s)/array-task(s) queued or running — pipeline busy, skipping."
    exit 0
fi

# --------------------------------------------------------------------------
# 3. Queue idle -> classify ledger rows.
# --------------------------------------------------------------------------
if [[ ! -s "$LEDGER" ]]; then
    record_status NO_LEDGER "no ledger at $LEDGER (or empty) — nothing to check."
    exit 0
fi

mapfile -t FAILED_STAMPS < <(awk -F'\t' '$2==0 {print $1}' "$LEDGER" | sort -u)
n_ok=$(awk -F'\t' '$2==1' "$LEDGER" | wc -l)
n_fail=${#FAILED_STAMPS[@]}

if (( n_fail == 0 )); then
    {
        echo "all_complete   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "completed      $n_ok"
    } > "$DONE_FLAG"
    record_status ALL_COMPLETE "$n_ok cycle(s) at status 1, 0 failed — nothing to do."
    exit 0
fi

# there ARE failures -> the completion flag is stale
rm -f "$DONE_FLAG"
log "queue idle; $n_ok completed, $n_fail failed: ${FAILED_STAMPS[*]}"

# --------------------------------------------------------------------------
# Attempt accounting: retry only inits under the cap; give up on the rest.
# --------------------------------------------------------------------------
touch "$ATTEMPTS"
: > "$RERUN_FILE"
declare -a TO_RUN=() GIVEN_UP=()

for stamp in "${FAILED_STAMPS[@]}"; do
    prev=$(awk -F'\t' -v k="$stamp" '$1==k {print $2}' "$ATTEMPTS" | tail -1)
    prev=${prev:-0}
    if (( prev >= MAX_ATTEMPTS )); then
        GIVEN_UP+=( "$stamp" )
        continue
    fi
    next=$(( prev + 1 ))
    # upsert attempts count
    awk -F'\t' -v k="$stamp" -v v="$next" '
        $1!=k { print }
        END   { print k "\t" v }
    ' "$ATTEMPTS" > "$ATTEMPTS.tmp" && mv "$ATTEMPTS.tmp" "$ATTEMPTS"
    TO_RUN+=( "$stamp" )
    echo "$stamp" | stamp_to_init >> "$RERUN_FILE"
done

if (( ${#GIVEN_UP[@]} > 0 )); then
    printf '%s\n' "${GIVEN_UP[@]}" | sort -u > "$GIVEUP"
    log "GIVING UP (>= $MAX_ATTEMPTS attempts) on: ${GIVEN_UP[*]}  (see $GIVEUP)"
fi

if (( ${#TO_RUN[@]} == 0 )); then
    record_status CAPPED "$n_fail failed but all have hit MAX_ATTEMPTS ($MAX_ATTEMPTS) — nothing submitted (see $GIVEUP)."
    exit 0
fi

log "rerun file: $RERUN_FILE"

if [[ "$DRY_RUN" == "YES" ]]; then
    record_status DRY_RUN "would resubmit ${#TO_RUN[@]} init(s): ${TO_RUN[*]} (giveup: ${GIVEN_UP[*]:-none})"
    sed 's/^/    /' "$RERUN_FILE" | tee -a "$LOG"
    exit 0
fi

# --------------------------------------------------------------------------
# Clear skip-guarded / partial output so a resubmit actually recomputes.
# GenEnsProd has SKIP_IF_OUTPUT_EXISTS=True, so a stale .nc would be reused.
# --------------------------------------------------------------------------
if [[ "$CLEAN_BEFORE_RERUN" == "YES" ]]; then
    for stamp in "${TO_RUN[@]}"; do
        rm -rf "$ROOT/metprd/GenEnsProd/$stamp" \
               "$ROOT/metprd/EnsembleStat/$stamp" \
               "$ROOT/metprd/MODE/$stamp" 2>/dev/null || true
    done
    log "cleared stale GenEnsProd/EnsembleStat/MODE output for retried inits."
fi

# --------------------------------------------------------------------------
# Launch. run_workflow.sh submits sequentially and (BATCH_SIZE>0) waits between
# batches; that's fine under cron — the next tick will see jobs in the queue and
# exit until they finish.
# --------------------------------------------------------------------------
cd "$ROOT"
record_status RESUBMITTED "starting ${#TO_RUN[@]} failed init(s): ${TO_RUN[*]} (giveup: ${GIVEN_UP[*]:-none})"
"$RUN_WORKFLOW" "$RERUN_FILE"
log "run_workflow.sh returned; reruns submitted."

