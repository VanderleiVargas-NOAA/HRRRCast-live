#!/bin/bash
#SBATCH --job-name=clean_obs
#SBATCH --output=logs/clean_obs_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[CLEAN_WALLTIME]

# set vars
INIT_TIME="@[INIT_TIME]"
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# MRMS obs location — per-init folder, MUST match job-fetch-data.sh.
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"
OBS_DIR="${DATAROOT}/obs/${INIT_STAMP}"

echo "In clean_obs, init=${INIT_STAMP}, obs_dir=${OBS_DIR}"

# SAFETY: require a non-empty init stamp and a path strictly under DATAROOT.
if [[ -z "${INIT_STAMP}" || -z "${DATAROOT}" || "${OBS_DIR}" != "${DATAROOT}/"* ]]; then
    echo "ABORT: refusing to remove '${OBS_DIR}'."
    exit 1
fi

if [[ ! -d "${OBS_DIR}" ]]; then
    echo "Nothing to clean: ${OBS_DIR} does not exist."
    exit 0
fi

# remove all fetched obs, then prune the now-empty parent dirs
find "${OBS_DIR}" -mindepth 1 -delete
rmdir -p "${OBS_DIR}" 2>/dev/null || true

echo "Done removing fetched obs under ${OBS_DIR}"
