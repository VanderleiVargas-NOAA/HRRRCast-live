#!/usr/bin/env bash
# diagnose_runs.sh — for each init marked incomplete (0) in the status ledger,
# find which pipeline job did NOT complete and show the tail of its log.
#
# Usage:
#   ./diagnose_runs.sh                       # all inits with status 0 in the ledger
#   ./diagnose_runs.sh 2026010106 2026010212 # only these init stamps
#   TAIL_LINES=40 ./diagnose_runs.sh         # show more log lines per failed job
#
# How it works:
#   logs/run_status.tsv          -> which inits are 0 (not completed)
#   logs/pipeline_jobids_<init>.txt -> the SLURM job ids that cycle submitted
#   sacct                        -> the terminal state of each id (authoritative)
#   logs/<jobname>_<jobid>.out   -> the log to read for the failing job
# If sacct no longer has the (month-old) jobs, it falls back to scanning the
# cycle's logs for failure markers.
set -uo pipefail

DATAROOT="${DATAROOT:-$(pwd)}"
LOGDIR="${DATAROOT}/logs"
LEDGER="${LOGDIR}/run_status.tsv"
TAIL_LINES="${TAIL_LINES:-25}"

# markers used only when sacct has no record of the job
MARKERS='DUE TO TIME LIMIT|CANCELLED|slurmstepd: error|srun: error|error:|Traceback|ERROR:|rc=[1-9]|command not found|No such file|Killed|[Oo]ut [Oo]f [Mm]emory|oom-kill'

inits=("$@")
if (( ${#inits[@]} == 0 )); then
    [[ -f "$LEDGER" ]] || { echo "No ledger at $LEDGER and no init stamps given." >&2; exit 1; }
    while IFS= read -r _s; do inits+=("$_s"); done < <(awk -F'\t' '$2==0 {print $1}' "$LEDGER")
fi
(( ${#inits[@]} )) || { echo "No incomplete (status 0) inits found."; exit 0; }

have_sacct=0; command -v sacct >/dev/null 2>&1 && have_sacct=1
echo "Diagnosing ${#inits[@]} init(s): ${inits[*]}"
(( have_sacct )) || echo "(sacct not available — falling back to log scanning)"

for init in "${inits[@]}"; do
    echo
    echo "==================================================================="
    echo "INIT ${init}"
    jf="${LOGDIR}/pipeline_jobids_${init}.txt"
    [[ -s "$jf" ]] || { echo "  (no job-id file: ${jf})"; continue; }

    if (( have_sacct )); then
        ids=$(paste -sd, "$jf")
        # one row per job / array task; show only the ones that are not COMPLETED
        sacct -j "$ids" -X --noheader --parsable2 \
              --format=JobID,JobIDRaw,JobName,State,ExitCode,Elapsed |
        while IFS='|' read -r jid raw jn st ec el; do
            [[ -n "$jid" ]] || continue
            [[ "${st%% *}" == COMPLETED ]] && continue
            log=$(ls -1 "${LOGDIR}/${jn}_${raw}.out" 2>/dev/null | head -1)
            [[ -z "$log" ]] && log=$(ls -1 "${LOGDIR}/"*"_${raw}.out" 2>/dev/null | head -1)
            echo "  ✗ ${jn:-?}  ${jid}  state=${st}  exit=${ec}  elapsed=${el}"
            echo "     log: ${log:-<not found>}"
            [[ -n "$log" && -f "$log" ]] && tail -n "$TAIL_LINES" "$log" | sed 's/^/       | /'
        done
    else
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            for log in "${LOGDIR}/"*"_${id}.out"; do
                [[ -f "$log" ]] || continue
                grep -qEi "$MARKERS" "$log" || continue
                echo "  ✗ $(basename "$log")"
                tail -n "$TAIL_LINES" "$log" | sed 's/^/       | /'
            done
        done < "$jf"
    fi
done

echo
echo "Done. To rerun the failed cycles, build a list and feed it to the driver:"
echo "  awk -F'\\t' '\$2==0{s=\$1; printf \"%s-%s-%sT%s\\n\", substr(s,1,4),substr(s,5,2),substr(s,7,2),substr(s,9,2)}' ${LEDGER} > rerun.txt"
echo "  ./run_workflow.sh rerun.txt"

