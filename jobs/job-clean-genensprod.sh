#!/bin/bash
#SBATCH --job-name=clean_genensprod
#SBATCH --output=logs/clean_genensprod_%j.out
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

# GenEnsProd output base (must match job-genensprod.sh).
MET_OUTPUT_BASE="${DATAROOT}/metprd/GenEnsProd"

# init stamp (YYYYMMDDHH) — the per-init output subdirectory
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"
GENENS_DIR="${MET_OUTPUT_BASE}/${INIT_STAMP}"

echo "In clean_genensprod, init=${INIT_STAMP}, dir=${GENENS_DIR}"

# SAFETY: require a non-empty init stamp and a path strictly under DATAROOT.
# (Empty INIT_STAMP would collapse to MET_OUTPUT_BASE and wipe all cycles.)
if [[ -z "${INIT_STAMP}" || -z "${DATAROOT}" || "${GENENS_DIR}" != "${DATAROOT}/"* ]]; then
    echo "ABORT: refusing to remove '${GENENS_DIR}'."
    exit 1
fi

if [[ ! -d "${GENENS_DIR}" ]]; then
    echo "Nothing to clean: ${GENENS_DIR} does not exist."
    exit 0
fi

# remove only this init's GenEnsProd output
find "${GENENS_DIR}" -mindepth 1 -delete
rmdir "${GENENS_DIR}" 2>/dev/null || true

echo "Done removing GenEnsProd output for ${INIT_STAMP} under ${GENENS_DIR}"
