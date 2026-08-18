#!/usr/bin/env bash
# timing_report.sh — per-job elapsed times + normalized rates from a completed run.
#
# Usage:
#   N_ENSEMBLES=10 LEAD_HOUR=6 N_GPUS=2 ./timing_report.sh logs/pipeline_jobids_2026053118.txt
#
# Reads SLURM accounting (sacct ElapsedRaw = seconds) for the pipeline job ids
# and prints, for each job, the elapsed wall time (max over array tasks), then
# the rates that scale with leads / members needed for proportional walltimes.
set -uo pipefail

JOBIDS_FILE=${1:?usage: N_ENSEMBLES=.. LEAD_HOUR=.. N_GPUS=.. ./timing_report.sh <pipeline_jobids_file>}
: "${N_ENSEMBLES:?set N_ENSEMBLES}"
: "${LEAD_HOUR:?set LEAD_HOUR}"
N_GPUS=${N_GPUS:-1}

[[ -f "$JOBIDS_FILE" ]] || { echo "no such file: $JOBIDS_FILE" >&2; exit 1; }
IDS=$(paste -sd, "$JOBIDS_FILE")
LEADS=$(( LEAD_HOUR + 1 ))                       # f00..fLEAD
MPT=$(( (N_ENSEMBLES + N_GPUS - 1) / N_GPUS ))   # members per GPU task (block dist.)

# job -> max elapsed seconds (max covers the slowest array task)
declare -A MAX
while IFS='|' read -r name sec jid st; do
    [[ "$jid" == *.* ]] && continue             # skip step rows (.batch/.0/.extern)
    [[ "$sec" =~ ^[0-9]+$ ]] || continue
    (( sec > ${MAX[$name]:-0} )) && MAX[$name]=$sec
done < <(sacct -j "$IDS" --noheader --parsable2 --format=JobName,ElapsedRaw,JobID,State)

echo "config: N_ENSEMBLES=$N_ENSEMBLES  LEAD_HOUR=$LEAD_HOUR  N_GPUS=$N_GPUS  (leads=$LEADS, members/GPU=$MPT)"
printf "\n%-18s %8s   %s\n" "job" "max_s" "mm:ss"
for n in "${!MAX[@]}"; do
    s=${MAX[$n]}
    printf "%-18s %8d   %02d:%02d\n" "$n" "$s" $((s/60)) $((s%60))
done | sort

rate() { awk -v v="${1:-0}" -v d="$2" 'BEGIN{ print (d>0)? v/d : 0 }'; }

echo
echo "== rates to feed proportional walltimes =="
printf "fcst   per (member*lead) : %6.2f s   [%ds / (%d members * %d leads)]\n" \
    "$(rate "${MAX[fcst]:-0}" $((MPT*LEADS)))" "${MAX[fcst]:-0}" "$MPT" "$LEADS"
for j in get_bcs make_bcs fetch_data genensprod gridstat; do
    printf "%-6s per lead          : %6.2f s   [%ds / %d leads]\n" \
        "$j" "$(rate "${MAX[$j]:-0}" "$LEADS")" "${MAX[$j]:-0}" "$LEADS"
done
echo
echo "Near-constant (use as base overhead): get_ics=${MAX[get_ics]:-?}s make_ics=${MAX[make_ics]:-?}s clean=${MAX[clean]:-?}s check=${MAX[check]:-?}s"
