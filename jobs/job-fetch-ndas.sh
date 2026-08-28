#!/bin/bash
#SBATCH --job-name=fetch_ndas
#SBATCH --output=logs/fetch_ndas_%j.out
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

# NDAS / HPSS settings.
# Per-NAM-cycle prepbufr tar; the name convention changed over the years, so try
# each candidate. {Y}=YYYY {YM}=YYYYMM {D}=YYYYMMDD {H}=cycle HH
ARCHIVE_DIR_TMPL='/NCEPPROD/hpssprod/runhistory/rh{Y}/{YM}/{D}'
TAR_NAMES=(
    "com_obsproc_v1.2_nam.{D}{H}.bufr.tar"
    "com_obsproc_v1.1_nam.{D}{H}.bufr.tar"
    "com_nam_prod_nam.{D}{H}.bufr.tar"
    "gpfs_dell1_nco_ops_com_nam_prod_nam.{D}{H}.bufr.tar"
    "com2_nam_prod_nam.{D}{H}.bufr.tar"
)

# HPSS client (htar). Adjust the module name if your system differs.
module load hpss 2>/dev/null || true

# init stamp (YYYYMMDDHH) and per-init output folder
DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH
INIT_STAMP="${DATE0}${HOUR0}"
OUTDIR="${DATAROOT}/obs/ndas/${INIT_STAMP}"
LOGDIR="${DATAROOT}/logs/fetch_ndas_${INIT_STAMP}"
mkdir -p "${OUTDIR}" "${LOGDIR}"

# For each forecast valid hour (init+0..init+LEAD): the prepbufr valid at that
# hour is tm{NN} of the 6-h cycle ENDING at ceil(vh/6)*6, where NN = cycleHour-vh
# (the freshest tm). 19..23z roll into the next day's 00 cycle (cycleHour=24).
# Record entries as "tar_date|cyc|NN|VH|valid_date".
ENTRIES=()
for (( h=0; h<=LEAD_HOUR; h++ )); do
    vt=$(date -u -d "${DATE0:0:4}-${DATE0:4:2}-${DATE0:6:2} ${HOUR0}:00:00 UTC +${h} hours" +%Y%m%d%H)
    vd=${vt:0:8}; vh=${vt:8:2}; H=$((10#${vh}))
    grp=$(( (H + 5) / 6 * 6 ))
    if (( grp == 24 )); then
        cyc="00"; fdate=$(date -u -d "${vd} +1 day" +%Y%m%d); absH=24
    elif (( grp == 0 )); then
        cyc="00"; fdate=${vd}; absH=0
    else
        cyc=$(printf "%02d" ${grp}); fdate=${vd}; absH=${grp}
    fi
    nn=$(printf "%02d" $(( absH - H )))          # tmNN
    ENTRIES+=( "${fdate}|${cyc}|${nn}|${vh}|${vd}" )
done

echo "In fetch_ndas, init=${INIT_STAMP}, outdir=${OUTDIR}"

# unique per-cycle tars, keyed "tar_date|cyc"
keys=$(printf '%s\n' "${ENTRIES[@]}" | awk -F'|' '{print $1"|"$2}' | sort -u)

overall_rc=0
for key in ${keys}; do
    IFS='|' read -r fdate cyc <<< "$key"
    y=${fdate:0:4}; ym=${fdate:0:6}
    archdir="${ARCHIVE_DIR_TMPL//\{Y\}/$y}"
    archdir="${archdir//\{YM\}/$ym}"
    archdir="${archdir//\{D\}/$fdate}"
    log="${LOGDIR}/${fdate}${cyc}.log"
    : > "${log}"

    # members wanted from this cycle's tar
    members=()
    for e in "${ENTRIES[@]}"; do
        IFS='|' read -r ef ec nn vh vd <<< "$e"
        [[ "${ef}|${ec}" == "${key}" ]] && members+=( "./nam.t${cyc}z.prepbufr.tm${nn}.nr" )
    done

    # try each candidate tar name until one extracts the members
    got=0
    for tmpl in "${TAR_NAMES[@]}"; do
        tarname="${tmpl//\{D\}/$fdate}"; tarname="${tarname//\{H\}/$cyc}"
        tarfile="${archdir}/${tarname}"
        echo "[${fdate}${cyc}] trying ${tarfile}" >> "${log}"
        if ( cd "${OUTDIR}" && htar -xvf "${tarfile}" "${members[@]}" ) >> "${log}" 2>&1; then
            got=1; echo "[${fdate}${cyc}] OK via ${tarname}"; break
        elif grep -qE 'HTAR:.*(-rw-|drwx)' "${log}"; then
            got=1; echo "[${fdate}${cyc}] OK (non-zero exit, files extracted) via ${tarname}"; break
        fi
    done
    (( got == 0 )) && { echo "[${fdate}${cyc}] FAILED — no candidate tar produced files (see ${log})" >&2; overall_rc=1; }

    # Rename this cycle's files to VALID-time names so nothing collides across
    # days (e.g. two t18z cycles in a 48-h run) and the layout is flat.
    for e in "${ENTRIES[@]}"; do
        IFS='|' read -r ef ec nn vh vd <<< "$e"
        [[ "${ef}|${ec}" == "${key}" ]] || continue
        src="${OUTDIR}/nam.t${cyc}z.prepbufr.tm${nn}.nr"
        dst="${OUTDIR}/nam.${vd}.t${vh}z.prepbufr.nr"
        [[ -f "$src" ]] && mv -f "$src" "$dst"
    done
done

echo "Done fetching NDAS for ${INIT_STAMP}. Files in ${OUTDIR}, per-cycle logs in ${LOGDIR}"
exit ${overall_rc}
