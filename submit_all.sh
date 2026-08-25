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

FCST_ACCNR=${FCST_ACCNR:-$ACCNR}
FCST_QOS=${FCST_QOS:-gpuwf}
FCST_RESERVATION=${FCST_RESERVATION:-}

if [ -n "$FCST_RESERVATION" ]; then
    FCST_RESERVATION="--reservation=${FCST_RESERVATION}"
fi

# Export configuration (specify variables and lead hours here)
EXPORT_OUTPUT_DIR=${EXPORT_OUTPUT_DIR:-"/scratch5/BMC/ai-datadepot/projects/HRRRCast"}
EXPORT_VARIABLES=${EXPORT_VARIABLES:-"APCP REFC"}
EXPORT_LEAD_HOURS=${EXPORT_LEAD_HOURS:-"1"}

hr=$(echo "$INIT_TIME" | grep -oP '\d{2}$')

# ---- proportional walltimes (calibrated from N_ENS=10, LEAD=6, N_GPUS=2) ----
LEADS=$(( LEAD_HOUR + 1 ))                          # f00..fLEAD
MPT=$(( (N_ENSEMBLES + N_GPUS - 1) / N_GPUS ))      # members per GPU task (block dist.)
SAFETY=${SAFETY:-1.5}                               # margin multiplier (time to spare)

secs_to_hms() { local s=$1; printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60)); }
# est base_s rate_s units -> ceil((base + rate*units) * SAFETY) seconds
est() { awk -v b="$1" -v r="$2" -v u="$3" -v k="$SAFETY" 'BEGIN{ printf "%d", (b + r*u)*k + 0.999 }'; }

# rate constants in SECONDS
FCST_BASE=120;      FCST_PER_STEP=25        # fcst: per (member * lead)
GETBCS_BASE=60;     GETBCS_PER_LEAD=3       # get_bcs: per lead
MAKEBCS_BASE=60;    MAKEBCS_PER_LEAD=41     # make_bcs: per lead
FETCH_BASE=60;      FETCH_PER_LEAD=5        # fetch_data: per lead
GENENS_BASE=120;    GENENS_PER_LEAD=150     # genensprod: per lead
GRIDSTAT_BASE=120;  GRIDSTAT_PER_LEAD=200   # gridstat: per lead

FCST_WALLTIME=$(secs_to_hms "$(est $FCST_BASE     $FCST_PER_STEP    $((MPT*LEADS)))")
GET_BCS_WALLTIME=$(secs_to_hms "$(est $GETBCS_BASE   $GETBCS_PER_LEAD  $LEADS)")
MAKE_BCS_WALLTIME=$(secs_to_hms "$(est $MAKEBCS_BASE  $MAKEBCS_PER_LEAD $LEADS)")
FETCH_WALLTIME=$(secs_to_hms "$(est $FETCH_BASE    $FETCH_PER_LEAD   $LEADS)")
GENENSPROD_WALLTIME=$(secs_to_hms "$(est $GENENS_BASE  $GENENS_PER_LEAD  $LEADS)")
GRIDSTAT_WALLTIME=$(secs_to_hms "$(est $GRIDSTAT_BASE $GRIDSTAT_PER_LEAD $LEADS)")

# fixed / near-constant jobs
GET_ICS_WALLTIME="00:10:00"
MAKE_ICS_WALLTIME="00:10:00"
EXPORT_WALLTIME="00:10:00"
CLEAN_WALLTIME="00:10:00"
CHECK_WALLTIME="00:05:00"
REPORT_WALLTIME="00:06:00"
PLOT_WALLTIME="00:30:00"

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
# Prevents a missing/optional job id from producing a malformed dependency
# (e.g. "afterok:123:" or "afterok:") that sbatch rejects.
dep_flag() {
    local t=$1; shift; local o=""
    for id in "$@"; do [[ -n "$id" ]] && o+=":$id"; done
    [[ -n "$o" ]] && printf -- '--dependency=%s%s' "$t" "$o"
}

source ./atparse.bash
if [ ! -d "$DATAROOT/logs" ]; then
    mkdir -p $DATAROOT/logs
fi
cd $DATAROOT

echo "PACKAGEROOT=$PACKAGEROOT,DATAROOT=$DATAROOT"

atparse < $PACKAGEROOT/jobs/job-get-ics.sh > $DATAROOT/logs/job-get-ics.sh
jobid1=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-get-ics.sh)
echo "Submitted job: $jobid1"

atparse < $PACKAGEROOT/jobs/job-get-bcs.sh > $DATAROOT/logs/job-get-bcs.sh
jobid2=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-get-bcs.sh)
echo "Submitted job: $jobid2"

atparse < $PACKAGEROOT/jobs/job-make-ics.sh > $DATAROOT/logs/job-make-ics.sh
jobid3=$(submit_with_check sbatch $(dep_flag afterok "$jobid1") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-make-ics.sh)
echo "Submitted job: $jobid3"

atparse < $PACKAGEROOT/jobs/job-make-bcs.sh > $DATAROOT/logs/job-make-bcs.sh
jobid4=$(submit_with_check sbatch $(dep_flag afterok "$jobid2") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-make-bcs.sh)
echo "Submitted job: $jobid4"

# submit forecasts as a job array over GPU slots; member range computed in job-fcst.sh
atparse < $PACKAGEROOT/jobs/job-fcst.sh > $DATAROOT/logs/job-fcst.sh
jobid5=$(submit_with_check sbatch $(dep_flag afterok "$jobid3" "$jobid4") --kill-on-invalid-dep=yes --array=0-$((N_GPUS-1)) --wait-all-nodes=1 ${FCST_RESERVATION} --parsable $DATAROOT/logs/job-fcst.sh)
echo "Submitted forecast job array: $jobid5"

# export forecasts to destination
export EXPORT_OUTPUT_DIR EXPORT_VARIABLES EXPORT_LEAD_HOURS EXPORT_WALLTIME
atparse < $PACKAGEROOT/jobs/job-export.sh > $DATAROOT/logs/job-export.sh
jobid_export=$(submit_with_check sbatch $(dep_flag afterok "$jobid5") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-export.sh)
echo "Submitted export job: $jobid_export"

# clean the run directory once forecasts and export complete, keeping only final products
atparse < $PACKAGEROOT/jobs/job-clean.sh > $DATAROOT/logs/job-clean.sh
jobid6=$(submit_with_check sbatch $(dep_flag afterok "$jobid5" "$jobid_export") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean.sh)
echo "Submitted clean job: $jobid6"

atparse < $PACKAGEROOT/jobs/job-check.sh > $DATAROOT/logs/job-check.sh
jobidC=$(submit_with_check sbatch $(dep_flag afterany "$jobid6") --parsable $DATAROOT/logs/job-check.sh)
echo "Submitted check job: $jobidC"

atparse < $PACKAGEROOT/jobs/job-fetch-mrms.sh > $DATAROOT/logs/job-fetch-mrms.sh
jobidF=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-fetch-mrms.sh)
echo "Submitted fetch job: $jobidF"

atparse < $PACKAGEROOT/jobs/job-fetch-ccpa.sh > $DATAROOT/logs/job-fetch-ccpa.sh
jobidFC=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-fetch-ccpa.sh)
echo "Submitted CCPA fetch job: $jobidFC"

atparse < $PACKAGEROOT/jobs/job-fetch-ndas.sh > $DATAROOT/logs/job-fetch-ndas.sh
jobidFN=$(submit_with_check sbatch --parsable $DATAROOT/logs/job-fetch-ndas.sh)
echo "Submitted NDAS fetch job: $jobidFN"

# gen_ens_prod: needs a complete run (check OK)
atparse < $PACKAGEROOT/jobs/job-genensprod.sh > $DATAROOT/logs/job-genensprod.sh
jobidG=$(submit_with_check sbatch $(dep_flag afterok "$jobidC") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-genensprod.sh)
echo "Submitted genensprod job: $jobidG"

# grid_stat: needs gen_ens_prod output AND the fetched obs
atparse < $PACKAGEROOT/jobs/job-gridstat.sh > $DATAROOT/logs/job-gridstat.sh
jobidS=$(submit_with_check sbatch $(dep_flag afterok "$jobidG" "$jobidF" "$jobidFN") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-gridstat.sh)
echo "Submitted gridstat job: $jobidS"

atparse < $PACKAGEROOT/jobs/job-clean-genensprod.sh > $DATAROOT/logs/job-clean-genensprod.sh
jobidGC=$(submit_with_check sbatch $(dep_flag afterok "$jobidS") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-genensprod.sh)
echo "Submitted clean-genensprod job: $jobidGC"

# remove the fetched obs once gridstat is done with them
atparse < $PACKAGEROOT/jobs/job-clean-obs.sh > $DATAROOT/logs/job-clean-obs.sh
jobidO=$(submit_with_check sbatch $(dep_flag afterok "$jobidS") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-obs.sh)
echo "Submitted clean-obs job: $jobidO"

# remove the remaining HRRRCast forecast output once verification is done
atparse < $PACKAGEROOT/jobs/job-clean-fcst.sh > $DATAROOT/logs/job-clean-fcst.sh
jobidP=$(submit_with_check sbatch $(dep_flag afterok "$jobidS" "$jobid_export") --kill-on-invalid-dep=yes --parsable $DATAROOT/logs/job-clean-fcst.sh)
echo "Submitted clean-fcst job: $jobidP"

# ------------------------------------------------------------------
# disk I/O report — runs after ALL pipeline jobs reach a terminal state
# ------------------------------------------------------------------
DATE_STAMP=${INIT_TIME%%T*}; DATE_STAMP=${DATE_STAMP//-/}; HOUR_STAMP=${INIT_TIME#*T}
JOBIDS_FILE="$DATAROOT/logs/pipeline_jobids_${DATE_STAMP}${HOUR_STAMP}.txt"
: > "$JOBIDS_FILE"
for v in "$jobid1" "$jobid2" "$jobid3" "$jobid4" "$jobid5" "$jobid_export" "$jobid6" \
         "$jobidC" "$jobidF" "$jobidFC" "$jobidG" "$jobidS" "$jobidGC" "$jobidO" "$jobidP"; do
    [[ -n "$v" ]] && echo "$v" >> "$JOBIDS_FILE"
done

DEP_AFTERANY=$(paste -sd: "$JOBIDS_FILE")
atparse < $PACKAGEROOT/jobs/job-diskreport.sh > $DATAROOT/logs/job-diskreport.sh
jobidR=$(submit_with_check sbatch --dependency=afterany:$DEP_AFTERANY --parsable $DATAROOT/logs/job-diskreport.sh)
echo "Submitted disk report job: $jobidR"
