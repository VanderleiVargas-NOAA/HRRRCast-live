#!/bin/bash
#SBATCH --job-name=fetch_ccpa
#SBATCH --output=logs/fetch_ccpa_%j.out
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

# CCPA / HPSS settings (hardcoded; edit here to change source).
#   tar:            /NCEPPROD/hpssprod/runhistory/rhYYYY/YYYYMM/YYYYMMDD/com_ccpa_v4.2_ccpa.YYYYMMDD.tar
#   internal dirs:  ./00 ./06 ./12 ./18 (+ gempak). Only the init's 6-h cycle dir is fetched.
TAR_TEMPLATE='/NCEPPROD/hpssprod/runhistory/rh{Y}/{YM}/{YMD}/com_ccpa_v4.2_ccpa.{YMD}.tar'

# HPSS client (htar). Adjust the module name if your system differs.
module load hpss 2>/dev/null || true

DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH
H=$((10#$HOUR0))

# CCPA cycle folder HH holds the 6 hours ENDING at HH (before, not ahead):
#   06 -> 01..06,  12 -> 07..12,  18 -> 13..18,  00 -> 19..00
# so the folder is ceil(H/6)*6, and 19..23 roll into the NEXT day's 00 folder.
grp=$(( (H + 5) / 6 * 6 ))                       # 0, 6, 12, 18, or 24
if (( grp == 24 )); then
    CYC="00"; FDATE=$(date -u -d "${DATE0} +1 day" +%Y%m%d)   # 19..23z -> next day 00
elif (( grp == 0 )); then
    CYC="00"; FDATE=${DATE0}                                  # 00z -> same day 00
else
    CYC=$(printf "%02d" ${grp}); FDATE=${DATE0}
fi

# Shared output keyed by (folder-date)+cycle so overlapping inits reuse the same download.
OUTBASE="${DATAROOT}/obs_ccpa/${FDATE}"
CYCLE_DIR="${OUTBASE}/${CYC}"
LOGDIR="${DATAROOT}/logs/fetch_ccpa_${FDATE}"
mkdir -p "${OUTBASE}" "${LOGDIR}"

echo "In fetch_ccpa, init=${INIT_TIME}, ccpa_folder=${FDATE}/${CYC}, target=${CYCLE_DIR}"

# Serialize concurrent inits that map to the same cycle (fetch jobs run in parallel).
exec 200>"${OUTBASE}/.${CYC}.lock"
flock 200

# Skip if a previous init in this 6-h block already fetched the folder.
if [[ -d "${CYCLE_DIR}" && -n "$(ls -A "${CYCLE_DIR}" 2>/dev/null)" ]]; then
    echo "CCPA cycle ${DATE0}/${CYC} already present — skipping download."
    exit 0
fi

y=${FDATE:0:4}; ym=${FDATE:0:6}
tarfile="${TAR_TEMPLATE//\{Y\}/$y}"
tarfile="${tarfile//\{YM\}/$ym}"
tarfile="${tarfile//\{YMD\}/$FDATE}"
log="${LOGDIR}/${FDATE}_${CYC}.log"

echo "Extracting ./${CYC} from ${tarfile}"
if ( cd "${OUTBASE}" && htar -xvf "${tarfile}" "./${CYC}" ) > "${log}" 2>&1; then
    echo "OK ${DATE0}/${CYC}"
else
    # htar sometimes exits non-zero on benign warnings — real failure only if nothing landed.
    if grep -qE 'HTAR:.*(-rw-|drwx)' "${log}"; then
        echo "OK ${DATE0}/${CYC} (non-zero exit, but files were extracted — see ${log})"
    else
        echo "FAILED ${DATE0}/${CYC} — see ${log}" >&2
        exit 1
    fi
fi

echo "Done fetching CCPA cycle ${DATE0}/${CYC}."
