#!/bin/bash
#SBATCH --job-name=clean_fcst
#SBATCH --output=logs/clean_fcst_%j.out
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

# extract date and hour
DATE=${INIT_TIME%%T*}
DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}

CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"

echo "In clean_fcst, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}"

# SAFETY: only ever operate on a path strictly under DATAROOT.
if [[ -z "${DATAROOT}" || "${CYCLE_DIR}" != "${DATAROOT}/"* ]]; then
    echo "ABORT: refusing to clean '${CYCLE_DIR}' (not under DATAROOT)."
    exit 1
fi

if [[ ! -d "${CYCLE_DIR}" ]]; then
    echo "Nothing to clean: ${CYCLE_DIR} does not exist."
    exit 0
fi

# remove all remaining HRRRCast output for this cycle (hrrrcast.* and hrrrcast_*)
find "${CYCLE_DIR}" -maxdepth 1 -type f -name 'hrrrcast*' -print -delete

# prune the cycle/date dirs if they are now empty (leaves any non-hrrrcast files intact)
rmdir "${CYCLE_DIR}" 2>/dev/null && rmdir "${DATAROOT}/${DATE}" 2>/dev/null

echo "Done removing HRRRCast output under ${CYCLE_DIR}"
