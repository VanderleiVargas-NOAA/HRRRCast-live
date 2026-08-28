#!/bin/bash
#SBATCH --job-name=fetch_ccpa
#SBATCH --output=logs/fetch_ccpa_%j.out
#SBATCH --partition=u1-service
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[FETCH_WALLTIME]

set -uo pipefail

# set vars (from atparse)
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# CCPA / HPSS settings (hardcoded; edit here to change source/target).
# CONUS 1-h accumulation only. Filenames inside each 6-h cycle folder are
# deterministic: ./{cyc}/ccpa.t{HH}z.{ACC}.{GRID}.gb2
TAR_TEMPLATE='/NCEPPROD/hpssprod/runhistory/rh{Y}/{YM}/{YMD}/com_ccpa_v4.2_ccpa.{YMD}.tar'
ACC='01h'                 # accumulation length
GRID='hrap.conus'         # grid: 0p125.conus 0p5.conus 1p0.conus hrap.conus ndgd2p5.conus ndgd5p0.conus

# HPSS client (htar). Adjust the module name if your system differs.
module load hpss 2>/dev/null || true

# init stamp (YYYYMMDDHH) and per-init output folder
DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH
INIT_STAMP="${DATE0}${HOUR0}"
OUTDIR="${DATAROOT}/obs/ccpa/${INIT_STAMP}"
LOGDIR="${DATAROOT}/logs/fetch_ccpa_${INIT_STAMP}"
mkdir -p "${OUTDIR}" "${LOGDIR}"

# For each forecast valid hour (init+1..init+LEAD), the 1-h CCPA accumulation
# ENDING at that hour lives in the 6-h cycle folder that ends at ceil(vh/6)*6,
# inside that folder-date's tar (19..23z roll into the next day's 00 folder).
# Record one entry per valid time as "tar_date|cyc|HH|valid_date".
ENTRIES=()
for (( h=1; h<=LEAD_HOUR; h++ )); do
    vt=$(date -u -d "${DATE0:0:4}-${DATE0:4:2}-${DATE0:6:2} ${HOUR0}:00:00 UTC +${h} hours" +%Y%m%d%H)
    vd=${vt:0:8}; vh=${vt:8:2}; H=$((10#${vh}))
    grp=$(( (H + 5) / 6 * 6 ))
    if (( grp == 24 )); then
        cyc="00"; fdate=$(date -u -d "${vd} +1 day" +%Y%m%d)
    elif (( grp == 0 )); then
        cyc="00"; fdate=${vd}
    else
        cyc=$(printf "%02d" ${grp}); fdate=${vd}
    fi
    ENTRIES+=( "${fdate}|${cyc}|${vh}|${vd}" )
done

echo "In fetch_ccpa, init=${INIT_STAMP}, acc=${ACC}, grid=${GRID}"

# unique tar dates to pull from
fdates=$(printf '%s\n' "${ENTRIES[@]}" | cut -d'|' -f1 | sort -u)

overall_rc=0
for fdate in ${fdates}; do
    y=${fdate:0:4}; ym=${fdate:0:6}
    tarfile="${TAR_TEMPLATE//\{Y\}/$y}"
    tarfile="${tarfile//\{YM\}/$ym}"
    tarfile="${tarfile//\{YMD\}/$fdate}"
    log="${LOGDIR}/${fdate}.log"

    # members wanted from this tar
    members=()
    for e in "${ENTRIES[@]}"; do
        IFS='|' read -r ef cyc vh vd <<< "$e"
        [[ "$ef" == "$fdate" ]] && members+=( "./${cyc}/ccpa.t${vh}z.${ACC}.${GRID}.gb2" )
    done

    echo "[$fdate] extracting ${#members[@]} file(s): ${members[*]}"
    if ( cd "${OUTDIR}" && htar -xvf "${tarfile}" "${members[@]}" ) > "${log}" 2>&1; then
        echo "[$fdate] OK"
    elif grep -qE 'HTAR:.*(-rw-|drwx)' "${log}"; then
        echo "[$fdate] OK (non-zero exit, but files were extracted — see ${log})"
    else
        echo "[$fdate] FAILED — see ${log}" >&2
        overall_rc=1
    fi

    # Rename this tar's files with their VALID date so nothing collides across
    # days (e.g. two t18z in a 48-h run), and flatten into OUTDIR.
    for e in "${ENTRIES[@]}"; do
        IFS='|' read -r ef cyc vh vd <<< "$e"
        [[ "$ef" == "$fdate" ]] || continue
        src="${OUTDIR}/${cyc}/ccpa.t${vh}z.${ACC}.${GRID}.gb2"
        dst="${OUTDIR}/ccpa.${vd}.t${vh}z.${ACC}.${GRID}.gb2"
        [[ -f "$src" ]] && mv -f "$src" "$dst"
    done
done

# remove the now-empty cycle subdirs (never rm -rf)
find "${OUTDIR}" -mindepth 1 -type d -empty -delete 2>/dev/null

echo "Done fetching CCPA for ${INIT_STAMP}. Files in ${OUTDIR}, per-date logs in ${LOGDIR}"
exit ${overall_rc}
