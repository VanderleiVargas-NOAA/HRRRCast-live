#!/bin/bash
#SBATCH --job-name=clean_pb2nc
#SBATCH --output=logs/clean_pb2nc_%j.out
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

# PB2NC output base (must match job-pb2nc.sh).
PB2NC_OUTPUT_BASE="${DATAROOT}/metprd/pb2nc"

# init stamp (YYYYMMDDHH) — the per-init output subdirectory
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"
PB2NC_DIR="${PB2NC_OUTPUT_BASE}/${INIT_STAMP}"

echo "In clean_pb2nc, init=${INIT_STAMP}, dir=${PB2NC_DIR}"

# SAFETY: require a non-empty init stamp and a path strictly under DATAROOT.
# (Empty INIT_STAMP would collapse to PB2NC_OUTPUT_BASE and wipe all cycles.)
if [[ -z "${INIT_STAMP}" || -z "${DATAROOT}" || "${PB2NC_DIR}" != "${DATAROOT}/"* ]]; then
    echo "ABORT: refusing to remove '${PB2NC_DIR}'."
    exit 1
fi

if [[ ! -d "${PB2NC_DIR}" ]]; then
    echo "Nothing to clean: ${PB2NC_DIR} does not exist."
    exit 0
fi

# remove only this init's pb2nc output
find "${PB2NC_DIR}" -mindepth 1 -delete
rmdir "${PB2NC_DIR}" 2>/dev/null || true

echo "Done removing pb2nc output for ${INIT_STAMP} under ${PB2NC_DIR}"

