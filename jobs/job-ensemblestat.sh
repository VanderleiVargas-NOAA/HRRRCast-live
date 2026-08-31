#!/bin/bash
#SBATCH --job-name=ensemblestat
#SBATCH --output=logs/ensemblestat_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[ENSEMBLESTAT_WALLTIME]

# set vars
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
N_ENSEMBLES=@[N_ENSEMBLES]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# cycle stamp (YYYYMMDDHH) and lead sequence (0,1,...,LEAD_HOUR)
DATE=${INIT_TIME%%T*}; DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}
INIT_STAMP="${DATE}${HOUR}"
LEAD_SEQ=$(seq -s, 0 "${LEAD_HOUR}"); LEAD_SEQ=${LEAD_SEQ%,}

# METplus config + I/O locations (edit here to change)
CONF="${PACKAGEROOT}/parm/EnsembleStat_SFC_HRRRCast.conf"
PB2NC_OUTPUT_DIR="${DATAROOT}/metprd/pb2nc/${INIT_STAMP}"                 # point obs (from job-pb2nc.sh)
ENSEMBLE_STAT_OUTPUT_DIR="${DATAROOT}/metprd/EnsembleStat/${INIT_STAMP}"

# load METplus (same environment as job-genensprod.sh)
module use /scratch4/BMC/fv3lam/Vanderlei.Vargas/Models/ufs-srweather-app/modulefiles
conda activate srw_app
module load wflow_ursa
module load build_ursa_intel  stack-oneapi/2024.2.1  stack-intel-oneapi-mpi/2021.13
module load metplus/6.0.0

mkdir -p "${ENSEMBLE_STAT_OUTPUT_DIR}"

# Build the ensemble member template for N_ENSEMBLES members (single-quoted so the
# METplus {init}/{lead} tokens stay literal; the mNN index is interpolated).
FCST_ENS_TEMPLATE=""
for (( m=0; m<N_ENSEMBLES; m++ )); do
    mm=$(printf "%02d" "$m")
    member='{init?fmt=%Y%m%d}/{init?fmt=%H}/hrrrcast.m'"${mm}"'.t{init?fmt=%H}z.pgrb2.f{lead?fmt=%HH}'
    if [[ -z "${FCST_ENS_TEMPLATE}" ]]; then
        FCST_ENS_TEMPLATE="${member}"
    else
        FCST_ENS_TEMPLATE="${FCST_ENS_TEMPLATE}, ${member}"
    fi
done

# values referenced as {ENV[...]} inside the METplus config
export INIT_STAMP LEAD_SEQ N_ENSEMBLES DATAROOT PB2NC_OUTPUT_DIR ENSEMBLE_STAT_OUTPUT_DIR FCST_ENS_TEMPLATE

echo "In ensemblestat, init=${INIT_STAMP}, leads=${LEAD_SEQ}, members=${N_ENSEMBLES}, fcst=${DATAROOT}, obs=${PB2NC_OUTPUT_DIR}, out=${ENSEMBLE_STAT_OUTPUT_DIR}"

run_metplus.py -c "${CONF}"

echo "Done ensemblestat for ${INIT_STAMP}"
