#!/bin/bash
#SBATCH --job-name=mode
#SBATCH --output=logs/mode_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[MODE_WALLTIME]

# Object-based verification (MET MODE) of the RAW HRRRCast member 0, for one init
# cycle. Loops (field x threshold): REFC vs MRMS composite reflectivity, and APCP
# vs CCPA 01h. Reads the member GRIB2 directly (hrrrcast.m00.tHHz.pgrb2.fLL) and
# the fetched obs; deterministic (no GenEnsProd / no NEP). Mirrors the per-init,
# atparse-template convention of job-gridstat.sh / job-gridstat-apcp.sh.

set -uo pipefail

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
CONF="${PACKAGEROOT}/parm/MODE_member_HRRRCast.conf"
MODE_MEMBER="00"                                                                # member 0 only (2-digit for hrrrcast.mNN)
MODE_OUTPUT_DIR="${DATAROOT}/metprd/MODE"
MODE_STAGING_DIR="${DATAROOT}/stage/MODE"

# obs sources (same locations the gridstat jobs use)
MRMS_OBS_DIR="${DATAROOT}/obs/mrms/${INIT_STAMP}"                                              # job-fetch-mrms.sh
CCPA_OBS_DIR="${DATAROOT}/obs/ccpa/${INIT_STAMP}"                                               # job-fetch-ccpa.sh

# load METplus (same environment as job-genensprod.sh / job-gridstat-apcp.sh)
module use /scratch4/BMC/fv3lam/Vanderlei.Vargas/Models/ufs-srweather-app/modulefiles
conda activate srw_app
module load wflow_ursa
module load build_ursa_intel  stack-oneapi/2024.2.1  stack-intel-oneapi-mpi/2021.13
module load metplus/6.0.0

# lead sequences: REFC has an f00; 1-h APCP is undefined at f00, so APCP starts at 1.
LEAD_SEQ_REFC=$(seq -s, 0 "${LEAD_HOUR}"); LEAD_SEQ_REFC=${LEAD_SEQ_REFC%,}
LEAD_SEQ_APCP=$(seq -s, 1 "${LEAD_HOUR}"); LEAD_SEQ_APCP=${LEAD_SEQ_APCP%,}

mkdir -p "${MODE_OUTPUT_DIR}" "${MODE_STAGING_DIR}" logs

# Field/threshold matrix (same as the research MODE job):
#   "FIELD:tag:conv_thresh:merge_thresh:conv_radius"
# merge_thresh must be BELOW conv_thresh (double-threshold merging).
# conv_radius in grid cells (3 km); min object area fixed at 16 cells (144 km^2)
# inside MODE_member_HRRRCast.conf.
MODE_MATRIX=(
    "REFC:ge20:>=20:>=10:4"
    "REFC:ge30:>=30:>=20:4"
    "REFC:ge40:>=40:>=30:4"
    "APCP:ge2.54:>=2.54:>=1.0:3"
    "APCP:ge12.7:>=12.7:>=6.35:3"
)

# vars shared across every MODE run (rest are set per matrix row below)
export INIT_STAMP DATAROOT MODE_MEMBER MODE_OUTPUT_DIR MODE_STAGING_DIR

worst=0
for spec in "${MODE_MATRIX[@]}"; do
    IFS=':' read -r field tag conv merge radius <<< "${spec}"

    # bind the obs source + field metadata for this field
    if [[ "${field}" == "APCP" ]]; then
        LEAD_SEQ="${LEAD_SEQ_APCP}"
        MODE_OBS_DIR="${CCPA_OBS_DIR}"
        MODE_OBS_NAME="APCP"
        MODE_OBS_LEVEL="A1"
        MODE_OBS_TEMPLATE='ccpa.{valid?fmt=%Y%m%d}.t{valid?fmt=%H}z.01h.hrap.conus.gb2'
        MODE_OBS_OPTIONS=''
        MODE_OBTYPE="CCPA"
    else
        LEAD_SEQ="${LEAD_SEQ_REFC}"
        MODE_OBS_DIR="${MRMS_OBS_DIR}"
        MODE_OBS_NAME="MergedReflectivityQComposite"
        MODE_OBS_LEVEL="Z500"
        MODE_OBS_TEMPLATE='MergedReflectivityQComposite_00.50_{valid?fmt=%Y%m%d}-{valid?fmt=%H%M%S}.grib2'
        MODE_OBS_OPTIONS='censor_thresh = lt-20; censor_val = -20.0;'
        MODE_OBTYPE="MRMS"
    fi

    export LEAD_SEQ MODE_FIELD="${field}" MODE_FCST_LEVEL="L0" \
           MODE_THRESH_TAG="${tag}" MODE_CONV_THRESH="${conv}" \
           MODE_MERGE_THRESH="${merge}" MODE_CONV_RADIUS="${radius}" \
           MODE_OBS_DIR MODE_OBS_NAME MODE_OBS_LEVEL MODE_OBS_TEMPLATE \
           MODE_OBS_OPTIONS MODE_OBTYPE

    echo "[$(date)] MODE mem${MODE_MEMBER} ${field} ${tag} (conv ${conv} merge ${merge} r${radius}) vs ${MODE_OBTYPE} init=${INIT_STAMP} leads=${LEAD_SEQ}"
    run_metplus.py -c "${CONF}"
    rc=$?
    (( rc > worst )) && worst=${rc}
done

echo "Done MODE for ${INIT_STAMP} (rc=${worst})"
# propagate the worst exit status so SLURM (and the finalize ledger) see failures
exit ${worst}

