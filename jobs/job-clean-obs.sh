#!/bin/bash
#SBATCH --job-name=clean_obs
#SBATCH --output=logs/clean_obs_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[CLEAN_WALLTIME]

set -uo pipefail

# set vars
INIT_TIME="@[INIT_TIME]"
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

DATE0=${INIT_TIME%%T*}; DATE0=${DATE0//-/}      # YYYYMMDD
HOUR0=${INIT_TIME#*T}                            # HH
INIT_STAMP="${DATE0}${HOUR0}"

OBS_ROOT="${DATAROOT}/obs"

echo "In clean_obs, init=${INIT_STAMP}, obs_root=${OBS_ROOT}"

# Each obs type is fetched into its own per-init folder, so cleanup is just
# removing this init's folders. Guarded to only ever act strictly under obs/.
for type in mrms ccpa ndas; do
    dir="${OBS_ROOT}/${type}/${INIT_STAMP}"
    if [[ -z "${INIT_STAMP}" || "${dir}" != "${OBS_ROOT}/"* ]]; then
        echo "  guard: refusing to remove '${dir}'"; continue
    fi
    if [[ -d "${dir}" ]]; then
        rm -rf "${dir}"
        echo "  removed ${dir}"
    else
        echo "  not present: ${dir}"
    fi
    # prune the now-empty type dir (leaves obs/ itself)
    rmdir "${OBS_ROOT}/${type}" 2>/dev/null || true
done

echo "Done clean_obs for init ${INIT_STAMP}."
