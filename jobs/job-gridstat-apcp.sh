#!/bin/bash
#SBATCH --job-name=gridstat-apcp
#SBATCH --output=logs/gridstat-apcp_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[GRIDSTAT_WALLTIME]

# Probabilistic precip verification: GenEnsProd APCP products vs CCPA 01h.
# Reads the SAME GenEnsProd NetCDF as the REFC gridstat (APCP fields live inside).

# set vars
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# cycle stamp (YYYYMMDDHH)
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"

# METplus config + I/O locations (edit here to change)
CONF="${PACKAGEROOT}/parm/GridStat_APCP_HRRRCast.conf"
MET_OUTPUT_BASE="${DATAROOT}/metprd/GenEnsProd"                                 # must match job-genensprod.sh
CCPA_OBS_DIR="${DATAROOT}/obs/ccpa/${INIT_STAMP}"                               # from job-fetch-ccpa.sh
GRIDSTAT_APCP_OUTPUT_BASE="${DATAROOT}/metprd/GridStat_apcp"
GRIDSTAT_APCP_STAGING_DIR="${DATAROOT}/stage/APCP_ensprob"

# load METplus (same environment as job-genensprod.sh)
module use /scratch4/BMC/fv3lam/Vanderlei.Vargas/Models/ufs-srweather-app/modulefiles
conda activate srw_app
module load wflow_ursa
module load build_ursa_intel  stack-oneapi/2024.2.1  stack-intel-oneapi-mpi/2021.13
module load metplus/6.0.0

# lead sequence starts at 1: 1-h APCP is undefined at f00, so there are no APCP
# ensemble products in the f00 GenEnsProd file — skip lead 0 to avoid a fatal
# "field not found" for precip.
LEAD_SEQ=$(seq -s, 1 "${LEAD_HOUR}"); LEAD_SEQ=${LEAD_SEQ%,}

mkdir -p "${GRIDSTAT_APCP_OUTPUT_BASE}" "${GRIDSTAT_APCP_STAGING_DIR}"

# values referenced as {ENV[...]} inside the METplus config
export INIT_STAMP LEAD_SEQ MET_OUTPUT_BASE CCPA_OBS_DIR GRIDSTAT_APCP_OUTPUT_BASE GRIDSTAT_APCP_STAGING_DIR

echo "In gridstat-apcp, init=${INIT_STAMP}, leads=${LEAD_SEQ}, fcst=${MET_OUTPUT_BASE}, obs=${CCPA_OBS_DIR}, out=${GRIDSTAT_APCP_OUTPUT_BASE}"

run_metplus.py -c "${CONF}"
rc=$?

echo "Done gridstat-apcp for ${INIT_STAMP} (rc=${rc})"
# propagate the tool's exit status so SLURM (and the finalize ledger) see failures
exit ${rc}

