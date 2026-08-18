#!/bin/bash
#SBATCH --job-name=fetch_data
#SBATCH --output=logs/fetch_data_%j.out
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

# MRMS / HPSS settings (hardcoded; edit here to change source/target)
TAR_TEMPLATE='/NCEPPROD/hpssprod/runhistory/rh{Y}/{YM}/{YMD}/dcom_ldmdata_obs.tar'
PATHSPEC='./upperair/mrms/conus/MergedReflectivityQComposite'
GUNZIP=1

# HPSS client (htar). Adjust the module name if your system differs.
module load hpss 2>/dev/null || true

# init stamp (YYYYMMDDHH) and per-init output folder
DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH
INIT_STAMP="${DATE0}${HOUR0}"
OUTDIR="${DATAROOT}/obs/${INIT_STAMP}"
LOGDIR="${DATAROOT}/logs/fetch_data_${INIT_STAMP}"
mkdir -p "${OUTDIR}" "${LOGDIR}"

# Build the set of required valid times (init + 0..LEAD hours), grouped by date.
# DATE_HOURS[YYYYMMDD] = "HH HH ..." for the hours needed on that date.
declare -A DATE_HOURS
for (( h=0; h<=LEAD_HOUR; h++ )); do
    vt=$(date -u -d "${DATE0:0:4}-${DATE0:4:2}-${DATE0:6:2} ${HOUR0}:00:00 UTC +${h} hours" +%Y%m%d%H)
    vd=${vt:0:8}; vh=${vt:8:2}
    DATE_HOURS[$vd]+="${vh} "
done

echo "In fetch_data, init=${INIT_STAMP}, lead=${LEAD_HOUR}, outdir=${OUTDIR}"
echo "Required dates: ${!DATE_HOURS[*]}"

# Fetch, per date, only the scans whose valid hour is in the required set.
overall_rc=0
for d in "${!DATE_HOURS[@]}"; do
    hours=$(echo "${DATE_HOURS[$d]}" | tr ' ' '\n' | grep -v '^$' | sort -u)
    hh_alt=$(echo "${hours}" | paste -sd'|' -)          # e.g. 18|19|20|...
    y=${d:0:4}; ym=${d:0:6}
    tarfile="${TAR_TEMPLATE//\{Y\}/$y}"
    tarfile="${tarfile//\{YM\}/$ym}"
    tarfile="${tarfile//\{YMD\}/$d}"
    log="${LOGDIR}/${d}.log"
    index="${LOGDIR}/${d}.index"
    members="${LOGDIR}/${d}.members"

    echo "[$d] hours: $(echo ${hours} | tr '\n' ' ')"

    # 1) list the MRMS subtree of the daily tar
    if ! htar -tvf "${tarfile}" "${PATHSPEC}" > "${index}" 2> "${log}"; then
        echo "[$d] WARN: htar -t returned non-zero (see ${log}); continuing with whatever was listed" >&2
    fi

    # 2) select member paths for the required valid hours (accept .grib2 or .grib2.gz)
    awk '{print $NF}' "${index}" \
        | grep -E "MergedReflectivityQComposite_00\.50_${d}-(${hh_alt})[0-9]{4}\.grib2(\.gz)?$" \
        | sort -u > "${members}"

    n=$(wc -l < "${members}")
    if [[ "${n}" -eq 0 ]]; then
        echo "[$d] FAILED: no MRMS scans matched the required hours (see ${index})" >&2
        overall_rc=1
        continue
    fi
    echo "[$d] extracting ${n} scan(s)"

    # 3) extract only those members into the per-init folder
    if ( cd "${OUTDIR}" && xargs -a "${members}" htar -xvf "${tarfile}" ) >> "${log}" 2>&1; then
        echo "[$d] OK"
    else
        if grep -qE 'HTAR:.*(-rw-|drwx)' "${log}"; then
            echo "[$d] OK (non-zero exit, but files were extracted — see ${log})"
        else
            echo "[$d] FAILED — see ${log}" >&2
            overall_rc=1
        fi
    fi
done

# gunzip any extracted MRMS files
if [[ "${GUNZIP}" == "1" ]]; then
    find "${OUTDIR}" -name '*.grib2.gz' -exec gunzip -f {} + 2>/dev/null
fi

echo "Done fetching MRMS for ${INIT_STAMP}. Per-date logs in ${LOGDIR}"
exit ${overall_rc}
