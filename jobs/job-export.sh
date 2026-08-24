#!/bin/bash
#SBATCH --job-name=export
#SBATCH --output=logs/export_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=@[EXPORT_WALLTIME]
#SBATCH --mem=16G

# Export selected variables from forecast GRIB2 files to a destination directory

module use /contrib/spack-stack/spack-stack-1.9.1/envs/ue-oneapi-2024.2.1/install/modulefiles/Core/
module load stack-oneapi
module load wgrib2

PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
N_ENSEMBLES=@[N_ENSEMBLES]
WGRIB2="@[WGRIB2]"

# Export configuration is supplied to submit_all.sh using environment variables
EXPORT_VARIABLES="${EXPORT_VARIABLES:-}"
EXPORT_LEAD_HOURS="${EXPORT_LEAD_HOURS:-}"
EXPORT_OUTPUT_DIR="${EXPORT_OUTPUT_DIR:-}"

if [ -z "$EXPORT_OUTPUT_DIR" ]; then
    echo "ERROR: EXPORT_OUTPUT_DIR not set" >&2
    exit 1
fi

if [ -z "$EXPORT_VARIABLES" ]; then
    echo "ERROR: EXPORT_VARIABLES not set" >&2
    exit 1
fi

if [ ! -d "$EXPORT_OUTPUT_DIR" ]; then
    echo "ERROR: EXPORT_OUTPUT_DIR '$EXPORT_OUTPUT_DIR' does not exist" >&2
    exit 1
fi

MATCH_PATTERN=":($(echo "$EXPORT_VARIABLES" | tr ',[:space:]' '|' | sed 's/|\{1,\}/|/g; s/^|//; s/|$//')):"
if [ "$MATCH_PATTERN" == ":():" ]; then
    echo "ERROR: No variables provided after parsing EXPORT_VARIABLES='$EXPORT_VARIABLES'" >&2
    exit 1
fi

DATE=${INIT_TIME%%T*}
DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}

SOURCE_DIR="${DATAROOT}/${DATE}/${HOUR}"
OUTPUT_DIR="${EXPORT_OUTPUT_DIR}/${DATE}/${HOUR}"
mkdir -p "$OUTPUT_DIR"

validate_export_variables() {
    local sample_idx="$1"
    local requested_vars="$2"
    local available_vars
    local invalid_vars=""
    local var

    if [ ! -f "$sample_idx" ]; then
        echo "WARNING: Cannot validate variables; sample index file '$sample_idx' not found" >&2
        return 0
    fi

    # Extract unique variable names from the index file (name is the fourth field)
    available_vars=$(cut -d':' -f4 "$sample_idx" | sort -u)

    # Check that each requested variable is in the list of available variables
    for var in $(echo "$requested_vars" | tr ',[:space:]' '\n' | grep -v '^$'); do
        if ! echo "$available_vars" | grep -q "^${var}$"; then
            invalid_vars="${invalid_vars}${var} "
        fi
    done

    if [ -n "$invalid_vars" ]; then
        echo "ERROR: Invalid EXPORT_VARIABLES: $invalid_vars" >&2
        echo "Available variables:" >&2
        echo "$available_vars" | sed 's/^/  /' >&2
        return 1
    fi

    return 0
}

# Validate EXPORT_VARIABLES against available variables in a sample GRIB2 index
sample_grib_idx=$(ls "${SOURCE_DIR}"/hrrrcast.m00.t${HOUR}z.pgrb2.*.idx 2>/dev/null | head -1)
if [ -n "$sample_grib_idx" ]; then
    validate_export_variables "$sample_grib_idx" "$EXPORT_VARIABLES"
    exit_code=$?
    if (( exit_code != 0 )); then
        exit "$exit_code"
    fi
fi

parse_lead_hours() {
    local spec="$1"
    local max_hour="$2"
    local expanded=""

    if [ -z "$spec" ]; then
        seq 0 "$max_hour"
        return
    fi

    for token in ${spec//,/ }; do
        if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
            expanded="${expanded} $(seq "${token%-*}" "${token#*-}")"
        elif [[ "$token" =~ ^[0-9]+$ ]]; then
            expanded="${expanded} ${token}"
        else
            echo "ERROR: Invalid lead hour token '$token'" >&2
            return 1
        fi
    done

    for lead in $(printf "%s\n" $expanded | sort -n -u); do
        if (( lead < 0 || lead > max_hour )); then
            echo "ERROR: Lead hour $lead is outside 0-${max_hour}" >&2
            return 1
        fi
        echo "$lead"
    done
}

LEADS=$(parse_lead_hours "$EXPORT_LEAD_HOURS" "$LEAD_HOUR")
exit_code=$?
if (( exit_code != 0 )); then
    exit "$exit_code"
fi

if [ -z "$LEADS" ]; then
    echo "ERROR: No lead hours selected" >&2
    exit 1
fi

export_member_lead() {
    local member="$1"
    local lead="$2"
    local member_padded
    local lead_padded
    local infile
    local outfile
    local logfile
    local logdir
    local exit_code

    member_padded=$(printf "%02d" "$member")
    lead_padded=$(printf "%02d" "$lead")
    infile="${SOURCE_DIR}/hrrrcast.m${member_padded}.t${HOUR}z.pgrb2.f${lead_padded}"
    outfile="${OUTPUT_DIR}/$(basename "$infile")"
    logdir="logs/${SLURM_JOB_NAME:-export}_${SLURM_JOB_ID:-manual}"
    logfile="${logdir}/$(basename "$outfile").log"

    mkdir -p "$logdir"
    exit_code=$?
    if (( exit_code != 0 )); then
        echo "ERROR: Failed to create log directory '$logdir'" >&2
        return "$exit_code"
    fi

    echo "Exporting $(basename "$infile") with match ${MATCH_PATTERN}"
    {
        echo "Input: $infile"
        echo "Output: $outfile"
        echo "Match: $MATCH_PATTERN"
        echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        grep -E "$MATCH_PATTERN" "${infile}.idx" | "$WGRIB2" "$infile" -i -grib "$outfile"
        exit_code=${PIPESTATUS[1]}
        echo "Finished: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Exit code: $exit_code"
    } > "$logfile" 2>&1

    if (( exit_code != 0 )); then
        echo "ERROR: wgrib2 extraction failed for '$infile'; see '$logfile'" >&2
        return "$exit_code"
    fi

    if [ ! -s "$outfile" ]; then
        echo "ERROR: Exported file '$outfile' is empty; check EXPORT_VARIABLES='$EXPORT_VARIABLES'" >&2
        return 1
    fi

    "$WGRIB2" "$outfile" > "${outfile}.idx" 2>> "$logfile"
    exit_code=$?
    if (( exit_code != 0 )); then
        echo "ERROR: Failed to create index '${outfile}.idx'; see '$logfile'" >&2
        return "$exit_code"
    fi
}

echo "Exporting forecast from $SOURCE_DIR to $OUTPUT_DIR"
echo "  N_ENSEMBLES: $N_ENSEMBLES"
echo "  EXPORT_VARIABLES: $EXPORT_VARIABLES"
echo "  EXPORT_LEAD_HOURS: ${EXPORT_LEAD_HOURS:-all}"

PARALLEL_JOBS=${SLURM_CPUS_PER_TASK:-1}
if (( PARALLEL_JOBS < 1 )); then
    PARALLEL_JOBS=1
fi

task_file=$(mktemp)
trap 'rm -f "$task_file"' EXIT

for member in $(seq 0 $((N_ENSEMBLES-1))); do
    for lead in $LEADS; do
        printf "%s %s\n" "$member" "$lead"
    done
done > "$task_file"

export_count=$(wc -l < "$task_file")
export -f export_member_lead
export WGRIB2 DATAROOT SOURCE_DIR OUTPUT_DIR HOUR EXPORT_VARIABLES MATCH_PATTERN

echo "Running up to ${PARALLEL_JOBS} exports in parallel"
xargs -n 2 -P "$PARALLEL_JOBS" bash -c 'export_member_lead "$1" "$2"' _ < "$task_file"
exit_code=$?
if (( exit_code != 0 )); then
    echo "ERROR: One or more export tasks failed" >&2
    exit "$exit_code"
fi

echo "Export job completed successfully (${export_count} files)"
