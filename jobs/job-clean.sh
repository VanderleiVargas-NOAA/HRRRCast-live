#!/bin/bash
#SBATCH --job-name=clean
#SBATCH --output=logs/clean_%j.out
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

# Files to keep. Hardcoded (NOT passed through atparse) so an empty
# substitution can never turn this into "delete everything".
# NOTE: *.pgrb2.f* also matches the *.idx sidecars, so those are kept too.
KEEP_GLOB='*.pgrb2.f*'

# extract date and hour
DATE=${INIT_TIME%%T*}
DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}

# cycle output directory
CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"

# job
echo "In clean, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, keep=${KEEP_GLOB}"

if [ ! -d "${CYCLE_DIR}" ]; then
    echo "Nothing to clean: ${CYCLE_DIR} does not exist."
    exit 0
fi

# SAFETY: how many files would we keep? If zero, something is wrong with the
# pattern — abort WITHOUT deleting rather than wiping the directory.
keep_count=$(find "${CYCLE_DIR}" -type f -name "${KEEP_GLOB}" | wc -l)
if [ "${keep_count}" -eq 0 ]; then
    echo "ABORT: no files match keep pattern '${KEEP_GLOB}' in ${CYCLE_DIR}; refusing to delete."
    exit 1
fi

# Delete everything that does NOT match KEEP_GLOB (keeps *.pgrb2.f* and *.idx).
find "${CYCLE_DIR}" -type f ! -name "${KEEP_GLOB}" -print -delete
find "${CYCLE_DIR}" -mindepth 1 -type d -empty -delete

echo "Done cleaning ${CYCLE_DIR}, kept ${keep_count} file(s) matching ${KEEP_GLOB}"
