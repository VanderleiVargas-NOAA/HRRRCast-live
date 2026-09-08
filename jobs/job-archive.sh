#!/bin/bash
#SBATCH --job-name=archive
#SBATCH --output=logs/archive_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[ARCHIVE_WALLTIME]

# Copy this cycle's forecast output to a keep-folder BEFORE cleanup removes it,
# but only for selected init hours (e.g. archive just the 00z cycles). For any
# other init hour this is a no-op, so it can be wired for every cycle safely.

set -uo pipefail

INIT_TIME="@[INIT_TIME]"
DATAROOT=@[DATAROOT]
ARCHIVE_DIR="@[ARCHIVE_DIR]"       # destination root
ARCHIVE_HOURS="@[ARCHIVE_HOURS]"   # init hours to archive: "00" or "00,12" or "00 06 12 18"

# cycle stamp
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"

# only archive the selected init hours; otherwise nothing to do
match=0
for h in ${ARCHIVE_HOURS//,/ }; do
    hh=$(printf "%02d" "$((10#$h))" 2>/dev/null || echo "$h")
    [[ "$hh" == "$HOUR" ]] && match=1
done
if (( ! match )); then
    echo "Init ${HOUR}z not in ARCHIVE_HOURS='${ARCHIVE_HOURS}' — nothing to archive."
    exit 0
fi

if [[ -z "${ARCHIVE_DIR}" ]]; then
    echo "ARCHIVE_DIR is empty — nothing to do."
    exit 0
fi

# what to copy: the forecast cycle directory (the hrrrcast.m*.pgrb2.f* products).
# Add more source dirs here if you also want to keep verification output, e.g.
#   "${DATAROOT}/metprd/GridStat_apcp/${INIT_STAMP}"
SRC="${DATAROOT}/${DATE}/${HOUR}"
DST="${ARCHIVE_DIR}/${DATE}/${HOUR}"

if [[ ! -d "${SRC}" ]]; then
    echo "Source ${SRC} does not exist — nothing to archive."
    exit 0
fi

mkdir -p "${DST}"
echo "Archiving ${SRC} -> ${DST}"
if command -v rsync >/dev/null 2>&1; then
    rsync -a "${SRC}/" "${DST}/"
    rc=$?
else
    cp -a "${SRC}/." "${DST}/"
    rc=$?
fi

echo "Done archiving ${INIT_STAMP} (rc=${rc})"
exit ${rc}

