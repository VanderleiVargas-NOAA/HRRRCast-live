#!/bin/bash
#SBATCH --job-name=pb2nc
#SBATCH --output=logs/pb2nc_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[PB2NC_WALLTIME]

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
CONF="${PACKAGEROOT}/parm/PB2NC_NDAS.conf"
NDAS_OBS_DIR="${DATAROOT}/obs/ndas/${INIT_STAMP}"            # per-init prepbufr (from job-fetch-ndas.sh)
PB2NC_OUTPUT_DIR="${DATAROOT}/metprd/pb2nc/${INIT_STAMP}"

# load METplus (same environment as job-genensprod.sh)
module use /scratch4/BMC/fv3lam/Vanderlei.Vargas/Models/ufs-srweather-app/modulefiles
conda activate srw_app
module load wflow_ursa
module load build_ursa_intel  stack-oneapi/2024.2.1  stack-intel-oneapi-mpi/2021.13
module load metplus/6.0.0

# valid window covering the forecast: init (f00) .. init+LEAD
VALID_BEG="${INIT_STAMP}"
VALID_END=$(date -u -d "${DATE:0:4}-${DATE:4:2}-${DATE:6:2} ${HOUR}:00:00 UTC +${LEAD_HOUR} hours" +%Y%m%d%H)

mkdir -p "${PB2NC_OUTPUT_DIR}"

# values referenced as {ENV[...]} inside the METplus config
export INIT_STAMP VALID_BEG VALID_END NDAS_OBS_DIR PB2NC_OUTPUT_DIR

echo "In pb2nc, init=${INIT_STAMP}, valid=${VALID_BEG}..${VALID_END}, obs=${NDAS_OBS_DIR}, out=${PB2NC_OUTPUT_DIR}"

run_metplus.py -c "${CONF}"

echo "Done pb2nc for ${INIT_STAMP}"
