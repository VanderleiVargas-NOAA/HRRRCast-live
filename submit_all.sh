#!/bin/bash

set -x

INIT_TIME=${1:-"2024-07-17T23"}
LEAD_HOUR=${2:-18}
N_ENSEMBLES=${3:-1}
N_GPUS=${4:-1}
PACKAGEROOT=${5:-`pwd`}
DATAROOT=${6:-`pwd`}
RUNPLOT=${7:-"YES"}
ENVMODE=${8:-``}

# cycle stamp YYYYMMDDHH — used by the status ledger, job-id file, disk report
INIT_DATE=${INIT_TIME%%T*}; INIT_DATE=${INIT_DATE//-/}
INIT_HOUR=${INIT_TIME#*T}
INIT_STAMP="${INIT_DATE}${INIT_HOUR}"

FCST_ACCNR=${FCST_ACCNR:-$ACCNR}
FCST_QOS=${FCST_QOS:-gpuwf}
FCST_RESERVATION=${FCST_RESERVATION:-}

if [ -n "$FCST_RESERVATION" ]; then
    FCST_RESERVATION="--reservation=${FCST_RESERVATION}"
fi

# ------------------------------------------------------------------
# Per-job on/off switches. Override any of these on the command line, e.g.
#   RUN_GENENSPROD=YES RUN_GRIDSTAT=YES ./submit_all.sh ...
# A disabled job is simply not submitted; its (empty) job id is dropped from
# downstream dependencies automatically by dep_flag().
# ------------------------------------------------------------------
RUN_GET_ICS=${RUN_GET_ICS:-YES}
RUN_GET_BCS=${RUN_GET_BCS:-YES}
RUN_MAKE_ICS=${RUN_MAKE_ICS:-YES}
RUN_MAKE_BCS=${RUN_MAKE_BCS:-YES}
RUN_FCST=${RUN_FCST:-YES}
RUN_EXPORT=${RUN_EXPORT:-YES}
RUN_CLEAN=${RUN_CLEAN:-YES}
RUN_FINALIZE=${RUN_FINALIZE:-YES}   # 0/1 status ledger (initialize + finalize)
RUN_FETCH_MRMS=${RUN_FETCH_MRMS:-YES}
RUN_FETCH_CCPA=${RUN_FETCH_CCPA:-YES}
RUN_FETCH_NDAS=${RUN_FETCH_NDAS:-YES}
RUN_PB2NC=${RUN_PB2NC:-YES}
RUN_ENSEMBLESTAT=${RUN_ENSEMBLESTAT:-YES}
RUN_GENENSPROD=${RUN_GENENSPROD:-YES}
RUN_GRIDSTAT=${RUN_GRIDSTAT:-YES}
RUN_GRIDSTAT_APCP=${RUN_GRIDSTAT_APCP:-YES}   # probabilistic precip (APCP) vs CCPA
RUN_CLEAN_GENENSPROD=${RUN_CLEAN_GENENSPROD:-YES}
RUN_CLEAN_PB2NC=${RUN_CLEAN_PB2NC:-YES}       # remove pb2nc point-obs after ensemblestat
RUN_ARCHIVE=${RUN_ARCHIVE:-YES}               # copy selected init hours to ARCHIVE_DIR before cleanup
RUN_CLEAN_OBS=${RUN_CLEAN_OBS:-YES}
RUN_CLEAN_FCST=${RUN_CLEAN_FCST:-YES}
RUN_DISKREPORT=${RUN_DISKREPORT:-YES}

# Export configuration (specify variables and lead hours here)
EXPORT_OUTPUT_DIR=${EXPORT_OUTPUT_DIR:-"/scratch5/BMC/ai-datadepot/projects/HRRRCast"}
EXPORT_LEAD_HOURS=${EXPORT_LEAD_HOURS:-"all"}
EXPORT_VARIABLE_CATEGORIES=${EXPORT_VARIABLE_CATEGORIES:-"surface-level surface-diagnostics"}
EXPORT_VARIABLES=${EXPORT_VARIABLES:-}
# NOTE: if both EXPORT_VARIABLES and EXPORT_VARIABLE_CATEGORIES are provided, their union
# will be used for export.

# Archive configuration (job-archive.sh copies matching init hours before cleanup)
ARCHIVE_DIR=${ARCHIVE_DIR:-"${DATAROOT}/archive"}   # destination root
ARCHIVE_HOURS=${ARCHIVE_HOURS:-"00"}                # which init hours to keep (e.g. "00" or "00,12")

hr=$(echo "$INIT_TIME" | grep -oP '\d{2}$')

# ---- proportional walltimes (calibrated from N_ENS=10, LEAD=6, N_GPUS=2) ----
LEADS=$(( LEAD_HOUR + 1 ))                          # f00..fLEAD
MPT=$(( (N_ENSEMBLES + N_GPUS - 1) / N_GPUS ))      # members per GPU task (block dist.)
SAFETY=${SAFETY:-1.5}                               # margin multiplier (time to spare)

secs_to_hms() { local s=$1; printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60)); }
# est base_s rate_s units -> ceil((base + rate*units) * SAFETY) seconds
est() { awk -v b="$1" -v r="$2" -v u="$3" -v k="$SAFETY" 'BEGIN{ printf "%d", (b + r*u)*k + 0.999 }'; }

# rate constants in SECONDS
FCST_BASE=420;      FCST_PER_STEP=35        # fcst: fixed model+data load+XLA warmup (~5min) + per (member * lead)
GETBCS_BASE=60;     GETBCS_PER_LEAD=3       # get_bcs: per lead
MAKEBCS_BASE=60;    MAKEBCS_PER_LEAD=41     # make_bcs: per lead
FETCH_BASE=600;     FETCH_PER_LEAD=120      # fetch: HPSS htar is tape-bound (mount+seek/scan), not 5s/lead
GENENS_BASE=120;    GENENS_PER_LEAD=200     # genensprod: per lead
GRIDSTAT_BASE=120;  GRIDSTAT_PER_LEAD=200   # gridstat: per lead
ENSSTAT_BASE=180;   ENSSTAT_PER_LEAD=180     # ensemblestat: per lead

FCST_WALLTIME=$(secs_to_hms "$(est $FCST_BASE     $FCST_PER_STEP    $((MPT*LEADS)))")
GET_BCS_WALLTIME=$(secs_to_hms "$(est $GETBCS_BASE   $GETBCS_PER_LEAD  $LEADS)")
MAKE_BCS_WALLTIME=$(secs_to_hms "$(est $MAKEBCS_BASE  $MAKEBCS_PER_LEAD $LEADS)")
FETCH_WALLTIME=$(secs_to_hms "$(est $FETCH_BASE    $FETCH_PER_LEAD   $LEADS)")
GENENSPROD_WALLTIME=$(secs_to_hms "$(est $GENENS_BASE  $GENENS_PER_LEAD  $LEADS)")
GRIDSTAT_WALLTIME=$(secs_to_hms "$(est $GRIDSTAT_BASE $GRIDSTAT_PER_LEAD $LEADS)")
ENSEMBLESTAT_WALLTIME=$(secs_to_hms "$(est $ENSSTAT_BASE $ENSSTAT_PER_LEAD $LEADS)")

# Cap the CPU/MET walltimes at the u1-compute limit (8:00:00); sbatch rejects any
# longer request. fcst runs on u1-h100 (7-day limit) and the fetch jobs on
# u1-service (1-day limit), so neither is capped here.
CPU_MAX_SEC=$(( 8*3600 ))
hms_to_secs() { local IFS=:; set -- $1; echo $(( 10#$1*3600 + 10#$2*60 + 10#$3 )); }
for _w in GET_BCS MAKE_BCS GENENSPROD GRIDSTAT ENSEMBLESTAT; do
    _v="${_w}_WALLTIME"
    if (( $(hms_to_secs "${!_v}") > CPU_MAX_SEC )); then
        printf -v "$_v" '%s' "$(secs_to_hms "$CPU_MAX_SEC")"
    fi
done

# fixed / near-constant jobs
GET_ICS_WALLTIME="00:10:00"
MAKE_ICS_WALLTIME="00:10:00"
EXPORT_WALLTIME="00:10:00"
CLEAN_WALLTIME="00:10:00"
FINALIZE_WALLTIME="00:05:00"
REPORT_WALLTIME="00:06:00"
PLOT_WALLTIME="00:30:00"
PB2NC_WALLTIME="00:15:00"
ARCHIVE_WALLTIME="00:30:00"

# set deadline only for near-realtime non-synoptic runs
INIT_EPOCH=$(date -u -d "${INIT_TIME}:00:00 UTC" +"%s")
NOW_EPOCH=$(date -u +"%s")
if [[ "$hr" =~ ^(00|06|12|18)$ ]]; then
    DEADLINE="2100-01-01T00:00:00"
elif (( NOW_EPOCH - INIT_EPOCH <= 6*3600 )); then
    DEADLINE=$(date -u -d "${INIT_TIME}:00:00 UTC +10 hours" +"%Y-%m-%dT%H:%M:%S")
else
    DEADLINE="2100-01-01T00:00:00"
fi

# set environment variables
PMM_POLL_SECONDS="60"
PMM_MIN_AGE_SECONDS="90"
NETCDF2GRIB_SECTION3=
WGRIB2="wgrib2"

# submit job and check for failures
submit_with_check() {
    local jobid
    jobid=$(eval "$@")
    if [[ $? -ne 0 || -z "$jobid" ]]; then
        echo "Failed to submit job: $*" >&2
        exit 1
    fi
    echo "$jobid"
}

# Build "--dependency=<type>:id1:id2" from non-empty ids only; empty -> no flag.
dep_flag() {
    local t=$1; shift; local o=""
    for id in "$@"; do [[ -n "$id" ]] && o+=":$id"; done
    [[ -n "$o" ]] && printf -- '--dependency=%s%s' "$t" "$o"
}

# on <SWITCH> -> true if the switch is enabled (YES/Y/ON/1, case-insensitive)
on() { case "$1" in YES|yes|Yes|Y|y|ON|on|1|true|TRUE) return 0;; *) return 1;; esac; }

# ---- status ledger (one line per init: 0 = started, 1 = completed) ----
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

source ./atparse.bash
if [ ! -d "$DATAROOT/logs" ]; then
    mkdir -p $DATAROOT/logs
fi
cd $DATAROOT

echo "PACKAGEROOT=$PACKAGEROOT,DATAROOT=$DATAROOT"

# status ledger: write 0 = started (inline, immediately at submission time). The
# finalize job flips it to 1 only if every pipeline job succeeds; otherwise it
# stays 0 = not completed.
if on "$RUN_FINALIZE"; then
    ledger_set "$INIT_STAMP" 0 "leads=${LEAD_HOUR} ens=${N_ENSEMBLES} gpus=${N_GPUS}"
    echo "Ledger: ${INIT_STAMP} -> 0 (started)"
fi

# ---- forecast pipeline ----
if on "$RUN_GET_ICS"; then
    atparse < $PACKAGEROOT/jobs/job-get-ics.sh > $DATAROOT/logs/job-get-ics.sh
    jobid1=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-get-ics.sh)
    echo "Submitted get-ics job: $jobid1"
fi

if on "$RUN_GET_BCS"; then
    atparse < $PACKAGEROOT/jobs/job-get-bcs.sh > $DATAROOT/logs/job-get-bcs.sh
    jobid2=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-get-bcs.sh)
    echo "Submitted get-bcs job: $jobid2"
fi

if on "$RUN_MAKE_ICS"; then
    atparse < $PACKAGEROOT/jobs/job-make-ics.sh > $DATAROOT/logs/job-make-ics.sh
    jobid3=$(submit_with_check sbatch $(dep_flag afterok "$jobid1") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-make-ics.sh)
    echo "Submitted make-ics job: $jobid3"
fi

if on "$RUN_MAKE_BCS"; then
    atparse < $PACKAGEROOT/jobs/job-make-bcs.sh > $DATAROOT/logs/job-make-bcs.sh
    jobid4=$(submit_with_check sbatch $(dep_flag afterok "$jobid2") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-make-bcs.sh)
    echo "Submitted make-bcs job: $jobid4"
fi

# submit forecasts as a job array over GPU slots; member range computed in job-fcst.sh
if on "$RUN_FCST"; then
    atparse < $PACKAGEROOT/jobs/job-fcst.sh > $DATAROOT/logs/job-fcst.sh
    jobid5=$(submit_with_check sbatch $(dep_flag afterok "$jobid3" "$jobid4") --kill-on-invalid-dep=yes --array=0-$((N_GPUS-1)) --wait-all-nodes=1 ${FCST_RESERVATION} --parsable $DATAROOT/logs/job-fcst.sh)
    echo "Submitted forecast job array: $jobid5"
fi

# export forecasts to destination
if on "$RUN_EXPORT"; then
    export EXPORT_OUTPUT_DIR EXPORT_LEAD_HOURS EXPORT_VARIABLE_CATEGORIES EXPORT_VARIABLES EXPORT_WALLTIME
    atparse < $PACKAGEROOT/jobs/job-export.sh > $DATAROOT/logs/job-export.sh
    jobid_export=$(submit_with_check sbatch $(dep_flag afterok "$jobid5") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-export.sh)
    echo "Submitted export job: $jobid_export"
fi

# clean the run directory once forecasts and export complete, keeping only final products
if on "$RUN_CLEAN"; then
    atparse < $PACKAGEROOT/jobs/job-clean.sh > $DATAROOT/logs/job-clean.sh
    jobid6=$(submit_with_check sbatch $(dep_flag afterok "$jobid5" "$jobid_export") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean.sh)
    echo "Submitted clean job: $jobid6"
fi

# ---- obs fetch (independent) ----
if on "$RUN_FETCH_MRMS"; then
    atparse < $PACKAGEROOT/jobs/job-fetch-mrms.sh > $DATAROOT/logs/job-fetch-mrms.sh
    jobidF=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-fetch-mrms.sh)
    echo "Submitted MRMS fetch job: $jobidF"
fi

if on "$RUN_FETCH_CCPA"; then
    atparse < $PACKAGEROOT/jobs/job-fetch-ccpa.sh > $DATAROOT/logs/job-fetch-ccpa.sh
    jobidFC=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-fetch-ccpa.sh)
    echo "Submitted CCPA fetch job: $jobidFC"
fi

if on "$RUN_FETCH_NDAS"; then
    atparse < $PACKAGEROOT/jobs/job-fetch-ndas.sh > $DATAROOT/logs/job-fetch-ndas.sh
    jobidFN=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-fetch-ndas.sh)
    echo "Submitted NDAS fetch job: $jobidFN"
fi

# ---- surface point verification (T2M/DPT/10m wind spread-skill) ----
if on "$RUN_PB2NC"; then
    atparse < $PACKAGEROOT/jobs/job-pb2nc.sh > $DATAROOT/logs/job-pb2nc.sh
    jobidPB=$(submit_with_check sbatch $(dep_flag afterok "$jobidFN") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-pb2nc.sh)
    echo "Submitted pb2nc job: $jobidPB"
fi

if on "$RUN_ENSEMBLESTAT"; then
    atparse < $PACKAGEROOT/jobs/job-ensemblestat.sh > $DATAROOT/logs/job-ensemblestat.sh
    jobidES=$(submit_with_check sbatch $(dep_flag afterok "$jobidPB" "$jobid5") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-ensemblestat.sh)
    echo "Submitted ensemblestat job: $jobidES"
fi

# ---- reflectivity probabilistic verification (GenEnsProd -> Grid-Stat) ----
if on "$RUN_GENENSPROD"; then
    atparse < $PACKAGEROOT/jobs/job-genensprod.sh > $DATAROOT/logs/job-genensprod.sh
    jobidG=$(submit_with_check sbatch $(dep_flag afterok "$jobid5") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-genensprod.sh)
    echo "Submitted genensprod job: $jobidG"
fi

if on "$RUN_GRIDSTAT"; then
    atparse < $PACKAGEROOT/jobs/job-gridstat.sh > $DATAROOT/logs/job-gridstat.sh
    jobidS=$(submit_with_check sbatch $(dep_flag afterok "$jobidG" "$jobidF" "$jobidFC") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-gridstat.sh)
    echo "Submitted gridstat job: $jobidS"
fi

# ---- precip probabilistic verification (GenEnsProd APCP -> Grid-Stat vs CCPA) ----
if on "$RUN_GRIDSTAT_APCP"; then
    atparse < $PACKAGEROOT/jobs/job-gridstat-apcp.sh > $DATAROOT/logs/job-gridstat-apcp.sh
    jobidSA=$(submit_with_check sbatch $(dep_flag afterok "$jobidG" "$jobidFC") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-gridstat-apcp.sh)
    echo "Submitted gridstat-apcp job: $jobidSA"
fi

if on "$RUN_CLEAN_GENENSPROD"; then
    atparse < $PACKAGEROOT/jobs/job-clean-genensprod.sh > $DATAROOT/logs/job-clean-genensprod.sh
    jobidGC=$(submit_with_check sbatch $(dep_flag afterok "$jobidS" "$jobidSA") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-genensprod.sh)
    echo "Submitted clean-genensprod job: $jobidGC"
fi

# remove the pb2nc point-obs NetCDF once its consumer (ensemblestat) is done
if on "$RUN_CLEAN_PB2NC"; then
    atparse < $PACKAGEROOT/jobs/job-clean-pb2nc.sh > $DATAROOT/logs/job-clean-pb2nc.sh
    jobidPBC=$(submit_with_check sbatch $(dep_flag afterok "$jobidES") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-pb2nc.sh)
    echo "Submitted clean-pb2nc job: $jobidPBC"
fi

# ---- cleanup ----
# remove the fetched obs once their consumers are done (gridstat: mrms/ccpa; pb2nc: ndas)
if on "$RUN_CLEAN_OBS"; then
    atparse < $PACKAGEROOT/jobs/job-clean-obs.sh > $DATAROOT/logs/job-clean-obs.sh
    jobidO=$(submit_with_check sbatch $(dep_flag afterok "$jobidS" "$jobidSA" "$jobidPB") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-obs.sh)
    echo "Submitted clean-obs job: $jobidO"
fi

# archive selected init hours (e.g. 00z) to ARCHIVE_DIR before the members are
# removed. Depends on the forecast (and clean, which trims to the pgrb2 products);
# a non-matching init hour makes the job a quick no-op.
if on "$RUN_ARCHIVE"; then
    export ARCHIVE_DIR ARCHIVE_HOURS ARCHIVE_WALLTIME
    atparse < $PACKAGEROOT/jobs/job-archive.sh > $DATAROOT/logs/job-archive.sh
    jobidA=$(submit_with_check sbatch $(dep_flag afterok "$jobid6" "$jobid5") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-archive.sh)
    echo "Submitted archive job: $jobidA"
fi

# remove the remaining HRRRCast members once every member-consumer is done
# (genensprod, ensemblestat), export finished, and the archive copy is done
if on "$RUN_CLEAN_FCST"; then
    atparse < $PACKAGEROOT/jobs/job-clean-fcst.sh > $DATAROOT/logs/job-clean-fcst.sh
    jobidP=$(submit_with_check sbatch $(dep_flag afterok "$jobidG" "$jobidES" "$jobid_export" "$jobidA") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-fcst.sh)
    echo "Submitted clean-fcst job: $jobidP"
fi

# ------------------------------------------------------------------
# Collect every submitted pipeline job id (skip empty/disabled ones). The status
# finalizer and the disk report both run once all of these reach a terminal state.
# ------------------------------------------------------------------
JOBIDS_FILE="$DATAROOT/logs/pipeline_jobids_${INIT_STAMP}.txt"
: > "$JOBIDS_FILE"
for v in "$jobid1" "$jobid2" "$jobid3" "$jobid4" "$jobid5" "$jobid_export" "$jobid6" \
         "$jobidF" "$jobidFC" "$jobidFN" "$jobidPB" "$jobidES" \
         "$jobidG" "$jobidS" "$jobidSA" "$jobidGC" "$jobidPBC" "$jobidO" "$jobidA" "$jobidP"; do
    [[ -n "$v" ]] && echo "$v" >> "$JOBIDS_FILE"
done
DEP_IDS=$(paste -sd: "$JOBIDS_FILE")

# status ledger, job 2 of 2: flip 0 -> 1, but ONLY if every pipeline job succeeds.
# afterok makes the dependency unsatisfiable the moment any job fails, so with
# --kill-on-invalid-dep this job is cancelled and the ledger stays 0.
if on "$RUN_FINALIZE" && [[ -n "$DEP_IDS" ]]; then
    atparse < $PACKAGEROOT/jobs/job-finalize.sh > $DATAROOT/logs/job-finalize.sh
    jobidFin=$(submit_with_check sbatch --dependency=afterok:$DEP_IDS --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-finalize.sh)
    echo "Submitted finalize job: $jobidFin"
fi

# disk I/O report (afterany: runs regardless of success/failure)
if on "$RUN_DISKREPORT" && [[ -n "$DEP_IDS" ]]; then
    atparse < $PACKAGEROOT/jobs/job-diskreport.sh > $DATAROOT/logs/job-diskreport.sh
    jobidR=$(submit_with_check sbatch --dependency=afterany:$DEP_IDS --parsable $DATAROOT/logs/job-diskreport.sh)
    echo "Submitted disk report job: $jobidR"
fi

