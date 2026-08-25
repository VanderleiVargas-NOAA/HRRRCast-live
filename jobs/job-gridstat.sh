#!/bin/bash
#SBATCH --job-name=gridstat
#SBATCH --output=logs/gridstat_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[GRIDSTAT_WALLTIME]

# set vars
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# METplus config + I/O locations (edit here to change)
CONF="${PACKAGEROOT}/parm/GridStat_REFC_HRRRCast.conf"
MET_OUTPUT_BASE="${DATAROOT}/metprd/GenEnsProd"          # must match job-genensprod.sh
GRIDSTAT_OUTPUT_BASE="${DATAROOT}/metprd/GridStat_ensprob"
GRIDSTAT_STAGING_DIR="${DATAROOT}/metprd/prob/stage/REFC_ensprob"

# load METplus (adjust module name/version for your system)
module use /scratch4/BMC/fv3lam/Vanderlei.Vargas/Models/ufs-srweather-app/modulefiles
conda activate srw_app
module load wflow_ursa
module load build_ursa_intel  stack-oneapi/2024.2.1  stack-intel-oneapi-mpi/2021.13 
module load metplus/6.0.0
# derive cycle stamp (YYYYMMDDHH) and lead sequence (0,1,...,LEAD_HOUR)
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"
LEAD_SEQ=$(seq -s, 0 "${LEAD_HOUR}"); LEAD_SEQ=${LEAD_SEQ%,}
MRMS_OBS_DIR="${DATAROOT}/obs/mrms/${INIT_STAMP}/upperair/mrms/conus/MergedReflectivityQComposite"

mkdir -p "${GRIDSTAT_OUTPUT_BASE}" "${GRIDSTAT_STAGING_DIR}"

# values referenced as {ENV[...]} inside the METplus config
export INIT_STAMP LEAD_SEQ MET_OUTPUT_BASE MRMS_OBS_DIR GRIDSTAT_OUTPUT_BASE GRIDSTAT_STAGING_DIR

echo "In gridstat, init=${INIT_STAMP}, leads=${LEAD_SEQ}, fcst=${MET_OUTPUT_BASE}, obs=${MRMS_OBS_DIR}, out=${GRIDSTAT_OUTPUT_BASE}"

run_metplus.py -c "${CONF}"

echo "Done gridstat for ${INIT_STAMP}"
