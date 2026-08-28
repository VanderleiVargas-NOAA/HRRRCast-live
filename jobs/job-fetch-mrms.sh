#!/bin/bash
#SBATCH --job-name=fetch_mrms
#SBATCH --output=logs/fetch_mrms_%j.out
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

# MRMS / HPSS settings (hardcoded; edit here to change source/target).
# CONUS composite reflectivity only; one scan per required valid hour.
TAR_TEMPLATE='/NCEPPROD/hpssprod/runhistory/rh{Y}/{YM}/{YMD}/dcom_ldmdata_obs.tar'
MRMS_SUBTREE='./upperair/mrms/conus/MergedReflectivityQComposite'
GUNZIP=1

# The scan cadence is NOT assumed — the nearest scan to each HH:00:00 is picked
# from the actual listing. TOLERANCE_SEC caps how far "nearest" may be: if the
# closest scan for an hour is farther than this (cadence change / data gap), that
# hour is skipped with a warning. Keep this >= Grid-Stat's OBS_..._FILE_WINDOW
# (±300 s) so we never fetch a scan Grid-Stat would reject anyway.
TOLERANCE_SEC=${TOLERANCE_SEC:-300}

# HPSS client (htar). Adjust the module name if your system differs.
module load hpss 2>/dev/null || true

# init stamp (YYYYMMDDHH) and per-init output folder
DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH
INIT_STAMP="${DATE0}${HOUR0}"
OUTDIR="${DATAROOT}/obs/mrms/${INIT_STAMP}"
LOGDIR="${DATAROOT}/logs/fetch_mrms_${INIT_STAMP}"
mkdir -p "${OUTDIR}" "${LOGDIR}"

# Required valid times (init + 0..LEAD hours), grouped by date.
declare -A DATE_HOURS
for (( h=0; h<=LEAD_HOUR; h++ )); do
    vt=$(date -u -d "${DATE0:0:4}-${DATE0:4:2}-${DATE0:6:2} ${HOUR0}:00:00 UTC +${h} hours" +%Y%m%d%H)
    vd=${vt:0:8}; vh=${vt:8:2}
    DATE_HOURS[$vd]+="${vh} "
done

echo "In fetch_mrms, init=${INIT_STAMP}, lead=${LEAD_HOUR}, outdir=${OUTDIR}"
echo "Required dates: ${!DATE_HOURS[*]}"

overall_rc=0
for d in "${!DATE_HOURS[@]}"; do
    hours=$(echo "${DATE_HOURS[$d]}" | tr ' ' '\n' | grep -v '^$' | sort -u)
    y=${d:0:4}; ym=${d:0:6}
    tarfile="${TAR_TEMPLATE//\{Y\}/$y}"
    tarfile="${tarfile//\{YM\}/$ym}"
    tarfile="${tarfile//\{YMD\}/$d}"
    log="${LOGDIR}/${d}.log"
    index="${LOGDIR}/${d}.index"
    members="${LOGDIR}/${d}.members"

    echo "[$d] hours: $(echo ${hours} | tr '\n' ' ')"

    # 1) list ONLY the CONUS composite-reflectivity subtree of the daily tar
    if ! htar -tvf "${tarfile}" "${MRMS_SUBTREE}" > "${index}" 2> "${log}"; then
        echo "[$d] WARN: htar -t returned non-zero (see ${log}); continuing with what was listed" >&2
    fi

    # 2) for each required hour, pick the ONE scan nearest HH:00:00, but only if
    #    it falls within TOLERANCE_SEC (cadence-agnostic; skips gaps with a warning).
    targets=$(for hh in ${hours}; do echo "${hh}:$(( 10#${hh} * 3600 ))"; done | paste -sd, -)
    awk -v targets="${targets}" -v tol="${TOLERANCE_SEC}" '
        BEGIN { n = split(targets, A, ",")
                for (i = 1; i <= n; i++) { split(A[i], kv, ":"); HH[i] = kv[1]; T[i] = kv[2] } }
        {
            p = $NF
            if (match(p, /-[0-9][0-9][0-9][0-9][0-9][0-9]\.grib2/)) {
                ts  = substr(p, RSTART+1, 6)
                sec = substr(ts,1,2)*3600 + substr(ts,3,2)*60 + substr(ts,5,2)
                for (i = 1; i <= n; i++) {
                    dd = sec - T[i]; if (dd < 0) dd = -dd
                    if (best[i] == "" || dd < bd[i]) { bd[i] = dd; best[i] = p }
                }
            }
        }
        END {
            for (i = 1; i <= n; i++) {
                if (best[i] == "")
                    printf("WARN: hour %s — no scan found\n", HH[i]) > "/dev/stderr"
                else if (bd[i] > tol)
                    printf("WARN: hour %s — nearest scan is %ds away (> %ds tolerance); skipping\n", HH[i], bd[i], tol) > "/dev/stderr"
                else
                    print best[i]
            }
        }
    ' "${index}" > "${members}" 2>> "${log}"

    # surface any per-hour warnings to the job output too
    grep -E "^WARN:" "${log}" 2>/dev/null | sed "s/^/[$d] /" >&2 || true

    sort -u -o "${members}" "${members}"
    n=$(wc -l < "${members}")
    if [[ "${n}" -eq 0 ]]; then
        echo "[$d] FAILED: no MRMS scans matched the required hours (see ${index})" >&2
        overall_rc=1
        continue
    fi
    echo "[$d] extracting ${n} scan(s) (one nearest each required hour)"

    # 3) extract just those members into the per-init folder
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

# Flatten: htar recreates the tar's internal path (./upperair/mrms/conus/...),
# but we want the scans directly under obs/mrms/${INIT_STAMP}/.
# Move per-file (portable), then delete only EMPTY dirs — never rm -rf, so a
# failed move can't destroy the data.
if [[ -d "${OUTDIR}/upperair" ]]; then
    find "${OUTDIR}/upperair" -type f -name 'MergedReflectivityQComposite_*' \
        -exec mv -f {} "${OUTDIR}/" \;
    find "${OUTDIR}/upperair" -depth -type d -empty -delete 2>/dev/null
fi

# gunzip extracted MRMS files
if [[ "${GUNZIP}" == "1" ]]; then
    find "${OUTDIR}" -maxdepth 1 -name '*.grib2.gz' -exec gunzip -f {} + 2>/dev/null
fi

echo "Done fetching MRMS for ${INIT_STAMP}. Files in ${OUTDIR}, per-date logs in ${LOGDIR}"
exit ${overall_rc}
