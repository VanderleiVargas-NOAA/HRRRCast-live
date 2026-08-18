#!/bin/bash
#SBATCH --job-name=genensprod
#SBATCH --output=logs/genensprod_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[GENENSPROD_WALLTIME]

# set vars
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
N_ENSEMBLES=@[N_ENSEMBLES]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# METplus config + output location (edit here to change)
CONF="${PACKAGEROOT}/parm/GenEnsProd_REFC_HRRRCast.conf"
MET_OUTPUT_BASE="${DATAROOT}/metprd/GenEnsProd"

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

mkdir -p "${MET_OUTPUT_BASE}"

# values referenced as {ENV[...]} inside the METplus config
export INIT_STAMP LEAD_SEQ DATAROOT MET_OUTPUT_BASE

echo "In genensprod, init=${INIT_STAMP}, leads=${LEAD_SEQ}, input=${DATAROOT}, out=${MET_OUTPUT_BASE}"

run_metplus.py -c "${CONF}"

echo "Done genensprod for ${INIT_STAMP}"
