#!/bin/bash
#SBATCH --job-name=diskreport
#SBATCH --output=logs/diskreport_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[REPORT_WALLTIME]

set -uo pipefail

# set vars
INIT_TIME="@[INIT_TIME]"
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"

JOBIDS_FILE="${DATAROOT}/logs/pipeline_jobids_${INIT_STAMP}.txt"
RAW="${DATAROOT}/logs/sacct_io_${INIT_STAMP}.psv"
OUT="${DATAROOT}/logs/disk_report_${INIT_STAMP}.txt"

if [[ ! -f "${JOBIDS_FILE}" ]]; then
    echo "ERROR: job id list not found: ${JOBIDS_FILE}" >&2
    exit 1
fi
IDS=$(paste -sd, "${JOBIDS_FILE}")

echo "In diskreport, init=${INIT_STAMP}, jobs=${IDS}"

# Per-step disk I/O in RAW BYTES. MaxDiskWrite/Read live on the step rows
# (JobID.batch, JobID.0, ...), so we sum over all step rows.
sacct -j "${IDS}" --noconvert --noheader --parsable2 \
    --format=JobID,JobName,State,MaxDiskWrite,MaxDiskRead,MaxRSS,Elapsed > "${RAW}"

# Sum write/read bytes across all rows that carry a numeric value.
read total_w total_r < <(awk -F'|' '
    { if ($4 ~ /^[0-9]+(\.[0-9]+)?$/) tw+=$4; if ($5 ~ /^[0-9]+(\.[0-9]+)?$/) tr+=$5 }
    END { printf "%.0f %.0f", tw+0, tr+0 }' "${RAW}")

to_mib() { awk -v b="$1" 'BEGIN{ printf "%.2f", b/1024/1024 }'; }
to_gib() { awk -v b="$1" 'BEGIN{ printf "%.3f", b/1024/1024/1024 }'; }

{
  echo "HRRRCast disk I/O report — init ${INIT_STAMP}"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Jobs: ${IDS}"
  echo
  echo "TOTAL bytes written : ${total_w} B  ($(to_mib ${total_w}) MiB, $(to_gib ${total_w}) GiB)"
  echo "TOTAL bytes read    : ${total_r} B  ($(to_mib ${total_r}) MiB, $(to_gib ${total_r}) GiB)"
  echo
  echo "Per-step detail (JobID | JobName | State | MaxDiskWrite | MaxDiskRead | MaxRSS | Elapsed):"
  column -t -s'|' "${RAW}"
} > "${OUT}"

if awk "BEGIN{exit !(${total_w}==0)}"; then
    echo "WARNING: MaxDiskWrite is 0 for all jobs — jobacct_gather may not be tracking disk I/O here." | tee -a "${OUT}"
fi

cat "${OUT}"
echo "Done diskreport. Wrote ${OUT}"
