#!/bin/bash
#SBATCH --job-name=fetch_ndas
#SBATCH --output=logs/fetch_ndas_%j.out
#SBATCH --partition=u1-service
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[FETCH_WALLTIME]

set -uo pipefail

# set vars (from atparse)
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# NDAS / HPSS settings (hardcoded; edit here to change source).
#   per-cycle NAM prepbufr tar; the tar name convention changed over the years,
#   so try each candidate in order until one exists.
#   {Y}=YYYY {YM}=YYYYMM {D}=YYYYMMDD {H}=cycle HH
ARCHIVE_DIR_TMPL='/NCEPPROD/hpssprod/runhistory/rh{Y}/{YM}/{D}'
TAR_NAMES=(
    "com2_nam_prod_nam.{D}{H}.bufr.tar"
    "gpfs_dell1_nco_ops_com_nam_prod_nam.{D}{H}.bufr.tar"
    "com_nam_prod_nam.{D}{H}.bufr.tar"
    "com_obsproc_v1.1_nam.{D}{H}.bufr.tar"
    "com_obsproc_v1.2_nam.{D}{H}.bufr.tar"
)
INTERNAL_TMPL='./nam.t{H}z.prepbufr.tm*.nr'

# HPSS client (htar). Adjust the module name if your system differs.
module load hpss 2>/dev/null || true

DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH

# Required (folder-date, NAM-cycle) pairs covering init + 0..LEAD hours.
# NAM cycle HH holds the 6 hours ENDING at HH (prepbufr tm06..tm00):
#   06 -> 01..06, 12 -> 07..12, 18 -> 13..18, 00 -> 19..00; 19..23 roll to next day 00.
declare -A CYCLE_SET
for (( h=0; h<=LEAD_HOUR; h++ )); do
    vt=$(date -u -d "${DATE0:0:4}-${DATE0:4:2}-${DATE0:6:2} ${HOUR0}:00:00 UTC +${h} hours" +%Y%m%d%H)
    vd=${vt:0:8}; vh=$((10#${vt:8:2}))
    grp=$(( (vh + 5) / 6 * 6 ))
    if (( grp == 24 )); then
        cyc="00"; fdate=$(date -u -d "${vd} +1 day" +%Y%m%d)
    elif (( grp == 0 )); then
        cyc="00"; fdate=${vd}
    else
        cyc=$(printf "%02d" ${grp}); fdate=${vd}
    fi
    CYCLE_SET["${fdate}/${cyc}"]=1
done

echo "In fetch_ndas, init=${INIT_TIME}, lead=${LEAD_HOUR}, cycles: ${!CYCLE_SET[*]}"

overall_rc=0
for key in "${!CYCLE_SET[@]}"; do
    fdate=${key%/*}; cyc=${key#*/}
    y=${fdate:0:4}; ym=${fdate:0:6}
    archdir="${ARCHIVE_DIR_TMPL//\{Y\}/$y}"
    archdir="${archdir//\{YM\}/$ym}"
    archdir="${archdir//\{D\}/$fdate}"
    internal="${INTERNAL_TMPL//\{H\}/$cyc}"

    OUTBASE="${DATAROOT}/obs/ndas/${fdate}"
    CYCLE_DIR="${OUTBASE}/${cyc}"
    LOGDIR="${DATAROOT}/logs/fetch_ndas_${fdate}"
    mkdir -p "${OUTBASE}" "${LOGDIR}"

    # Do the locked, skip-if-present, try-each-tar work in a subshell so the
    # flock (fd 9) is released automatically when the subshell exits.
    (
        flock 9

        if [[ -d "${CYCLE_DIR}" && -n "$(ls -A "${CYCLE_DIR}" 2>/dev/null)" ]]; then
            echo "NDAS ${fdate}/${cyc} already present — skipping."
            exit 0
        fi
        mkdir -p "${CYCLE_DIR}"

        for tmpl in "${TAR_NAMES[@]}"; do
            tarname="${tmpl//\{D\}/$fdate}"; tarname="${tarname//\{H\}/$cyc}"
            tarfile="${archdir}/${tarname}"
            log="${LOGDIR}/${fdate}${cyc}_${tarname}.log"
            echo "[${fdate}/${cyc}] trying ${tarfile}"
            if ( cd "${CYCLE_DIR}" && htar -xvf "${tarfile}" "${internal}" ) > "${log}" 2>&1 \
               && [[ -n "$(ls -A "${CYCLE_DIR}" 2>/dev/null)" ]]; then
                echo "[${fdate}/${cyc}] OK via ${tarname}"
                exit 0
            elif grep -qE 'HTAR:.*(-rw-|drwx)' "${log}" 2>/dev/null; then
                echo "[${fdate}/${cyc}] OK (non-zero exit, files extracted) via ${tarname}"
                exit 0
            fi
        done

        echo "[${fdate}/${cyc}] FAILED — no candidate tar produced files (see ${LOGDIR})" >&2
        exit 1
    ) 9>"${OUTBASE}/.${cyc}.lock"
    (( $? != 0 )) && overall_rc=1
done

echo "Done fetching NDAS for init ${INIT_TIME}."
exit ${overall_rc}
