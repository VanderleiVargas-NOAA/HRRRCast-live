#!/bin/bash
#SBATCH --job-name=export
#SBATCH --output=logs/export_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
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
EXPORT_OUTPUT_DIR="${EXPORT_OUTPUT_DIR:-}"
EXPORT_LEAD_HOURS="${EXPORT_LEAD_HOURS:-}"
EXPORT_VARIABLES="${EXPORT_VARIABLES:-}"
EXPORT_VARIABLES_EXPLICIT="$EXPORT_VARIABLES"
EXPORT_VARIABLE_CATEGORIES="${EXPORT_VARIABLE_CATEGORIES:-}"
EXPORT_ALL_VARIABLES="NO"

if [ -z "$EXPORT_OUTPUT_DIR" ]; then
    echo "ERROR: EXPORT_OUTPUT_DIR not set" >&2
    exit 1
fi

if [ ! -d "$EXPORT_OUTPUT_DIR" ]; then
    echo "ERROR: EXPORT_OUTPUT_DIR '$EXPORT_OUTPUT_DIR' does not exist" >&2
    exit 1
fi

valid_export_categories() {
    printf "%s\n" \
    "pressure-level" \
    "surface-level" \
    "surface-diagnostics" \
    "column-integrated" \
    "precipitation-diagnostics" \
    "wind-diagnostics" \
    "convective-diagnostics" \
    "updraft-helicity" \
    "vertical-velocity-extrema" \
    "isotherm-diagnostics" \
    "all"
}

selectors_for_category() {
    local category="$1"

    case "$category" in
        pressure-level)
            printf "%s\n" ":(UGRD|VGRD|VVEL|TMP|HGT|SPFH):[0-9]+ mb:"
            ;;
        surface-level)
            printf "%s\n" \
                ":PRES:surface:" \
                ":MSLMA:mean sea level:" \
                ":REFC:entire atmosphere:" \
                ":TMP:2 m above ground:" \
                ":UGRD:10 m above ground:" \
                ":VGRD:10 m above ground:" \
                ":UGRD:80 m above ground:" \
                ":VGRD:80 m above ground:" \
                ":DPT:2 m above ground:" \
                ":TCDC:entire atmosphere:" \
                ":LCDC:low cloud layer:" \
                ":MCDC:middle cloud layer:" \
                ":HCDC:high cloud layer:" \
                ":VIS:surface:" \
                ":APCP:surface:" \
                ":HGT:surface:" \
                ":HGT:cloud ceiling:" \
                ":CAPE:surface:" \
                ":CIN:surface:"
            ;;
        surface-diagnostics)
            printf "%s\n" \
                ":RH:2 m above ground:" \
                ":SPFH:2 m above ground:" \
                ":POT:2 m above ground:"
            ;;
        column-integrated)
            printf "%s\n" ":PWAT:entire atmosphere:"
            ;;
        precipitation-diagnostics)
            printf "%s\n" ":CRAIN:surface:" ":CFRZR:surface:"
            ;;
        wind-diagnostics)
            printf "%s\n" ":GUST:surface:" ":WIND:10 m above ground:"
            ;;
        convective-diagnostics)
            printf "%s\n" \
                ":VUCSH:1000-0 m above ground:" \
                ":VVCSH:1000-0 m above ground:" \
                ":VUCSH:6000-0 m above ground:" \
                ":VVCSH:6000-0 m above ground:" \
                ":RELV:1000-0 m above ground:" \
                ":RELV:2000-0 m above ground:" \
                ":USTM:0-6000 m above ground:" \
                ":VSTM:0-6000 m above ground:" \
                ":HLCY:1000-0 m above ground:" \
                ":HLCY:3000-0 m above ground:"
            ;;
        updraft-helicity)
            printf "%s\n" \
                ":MXUPHL:2000-0 m above ground:" \
                ":MNUPHL:2000-0 m above ground:" \
                ":MXUPHL:3000-0 m above ground:" \
                ":MNUPHL:3000-0 m above ground:" \
                ":MXUPHL:5000-2000 m above ground:" \
                ":MNUPHL:5000-2000 m above ground:"
            ;;
        vertical-velocity-extrema)
            printf "%s\n" ":MAXUVV:100-1000 mb:" ":MAXDVV:100-1000 mb:"
            ;;
        isotherm-diagnostics)
            printf "%s\n" \
                ":HGT:0C isotherm:" \
                ":UGRD:0C isotherm:" \
                ":VGRD:0C isotherm:" \
                ":WIND:0C isotherm:" \
                ":SPFH:0C isotherm:" \
                ":RH:0C isotherm:"
            ;;
        *)
            return 1
            ;;
    esac
}

selectors_for_variables() {
    local var

    for var in $(echo "$1" | tr ',[:space:]' '\n' | grep -v '^$'); do
        printf ":%s:\n" "$var"
    done
}

deduplicate_selectors() {
    awk 'NF && !seen[$0]++'
}

join_selectors() {
    local pattern=""
    local selector

    while IFS= read -r selector; do
        pattern="${pattern}${pattern:+|}${selector}"
    done

    printf "%s\n" "$pattern"
}

EXPORT_SELECTORS=$(selectors_for_variables "$EXPORT_VARIABLES")

for category in ${EXPORT_VARIABLE_CATEGORIES//,/ }; do
    if [ "$category" == "all" ]; then
        EXPORT_ALL_VARIABLES="YES"
    else
        category_selectors=$(selectors_for_category "$category")
        exit_code=$?
        if (( exit_code != 0 )); then
            echo "ERROR: Invalid EXPORT_VARIABLE_CATEGORIES token '$category'" >&2
            echo "Valid categories:" >&2
            valid_export_categories >&2
            exit 1
        fi
        EXPORT_SELECTORS=$(printf "%s\n%s\n" "$EXPORT_SELECTORS" "$category_selectors")
    fi
done

if [ "$EXPORT_ALL_VARIABLES" != "YES" ]; then
    EXPORT_SELECTORS=$(printf "%s\n" "$EXPORT_SELECTORS" | deduplicate_selectors)
    MATCH_PATTERN=$(printf "%s\n" "$EXPORT_SELECTORS" | join_selectors)
    if [ -z "$MATCH_PATTERN" ]; then
        echo "ERROR: No variables provided after parsing EXPORT_VARIABLES='$EXPORT_VARIABLES' and EXPORT_VARIABLE_CATEGORIES='$EXPORT_VARIABLE_CATEGORIES'" >&2
        exit 1
    fi
else
    EXPORT_VARIABLES="all"
    EXPORT_SELECTORS=""
    MATCH_PATTERN=""
fi

DATE=${INIT_TIME%%T*}
DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}

SOURCE_DIR="${DATAROOT}/${DATE}/${HOUR}"
OUTPUT_DIR="${EXPORT_OUTPUT_DIR}/${DATE}/${HOUR}"
mkdir -p "$OUTPUT_DIR"

validate_export_selectors() {
    local sample_idx="$1"
    local selectors="$2"
    local invalid_selectors=""
    local selector

    if [ ! -f "$sample_idx" ]; then
        echo "WARNING: Cannot validate export selectors; sample index file '$sample_idx' not found" >&2
        return 0
    fi

    while IFS= read -r selector; do
        if [ -n "$selector" ] && ! grep -Eq "$selector" "$sample_idx"; then
            invalid_selectors="${invalid_selectors}${invalid_selectors:+ }${selector}"
        fi
    done <<EOF
$selectors
EOF

    if [ -n "$invalid_selectors" ]; then
        echo "ERROR: Export selectors did not match sample index: $invalid_selectors" >&2
        echo "Available fields:" >&2
        cut -d':' -f4,5 "$sample_idx" | sort -u | sed 's/^/  /' >&2
        return 1
    fi

    return 0
}

# Validate selectors against available records in a sample GRIB2 index
sample_grib_idx=$(ls "${SOURCE_DIR}"/hrrrcast.m00.t${HOUR}z.pgrb2.*.idx 2>/dev/null | head -1)
if [ "$EXPORT_ALL_VARIABLES" != "YES" ] && [ -n "$sample_grib_idx" ]; then
    validate_export_selectors "$sample_grib_idx" "$EXPORT_SELECTORS"
    exit_code=$?
    if (( exit_code != 0 )); then
        exit "$exit_code"
    fi
fi

parse_lead_hours() {
    local spec="$1"
    local max_hour="$2"
    local expanded=""

    if [ -z "$spec" ] || [ "$spec" == "all" ]; then
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

    if [ "$EXPORT_ALL_VARIABLES" == "YES" ]; then
        echo "Exporting $(basename "$infile") with all variables"
    else
        echo "Exporting $(basename "$infile") with matched variables"
    fi
    {
        echo "Input: $infile"
        echo "Output: $outfile"
        if [ "$EXPORT_ALL_VARIABLES" == "YES" ]; then
            echo "Match: all variables"
        else
            echo "Match: $MATCH_PATTERN"
        fi
        echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        if [ "$EXPORT_ALL_VARIABLES" == "YES" ]; then
            cp -f "$infile" "$outfile"
            exit_code=$?
        else
            grep -E "$MATCH_PATTERN" "${infile}.idx" | "$WGRIB2" "$infile" -i -grib "$outfile"
            exit_code=${PIPESTATUS[1]}
        fi
        echo "Finished: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Exit code: $exit_code"
    } > "$logfile" 2>&1

    if (( exit_code != 0 )); then
        echo "ERROR: Export failed for '$infile'; see '$logfile'" >&2
        return "$exit_code"
    fi

    if [ ! -s "$outfile" ]; then
        if [ "$EXPORT_ALL_VARIABLES" == "YES" ]; then
            echo "ERROR: Exported file '$outfile' is empty; check source file '$infile'" >&2
        else
            echo "ERROR: Exported file '$outfile' is empty; check EXPORT_VARIABLES='$EXPORT_VARIABLES'" >&2
        fi
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
echo "  EXPORT_LEAD_HOURS: ${EXPORT_LEAD_HOURS:-all}"
echo "  EXPORT_VARIABLE_CATEGORIES: ${EXPORT_VARIABLE_CATEGORIES:-none}"
echo "  EXPORT_VARIABLES_EXPLICIT: ${EXPORT_VARIABLES_EXPLICIT:-none}"
if [ "$EXPORT_ALL_VARIABLES" != "YES" ]; then
    echo "  EXPORT_MATCH_PATTERN: $MATCH_PATTERN"
else
    echo "  Exporting all variables"
fi

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
export WGRIB2 DATAROOT SOURCE_DIR OUTPUT_DIR HOUR EXPORT_ALL_VARIABLES EXPORT_VARIABLES MATCH_PATTERN

echo "Running up to ${PARALLEL_JOBS} exports in parallel"
xargs -n 2 -P "$PARALLEL_JOBS" bash -c 'export_member_lead "$1" "$2"' _ < "$task_file"
exit_code=$?
if (( exit_code != 0 )); then
    echo "ERROR: One or more export tasks failed" >&2
    exit "$exit_code"
fi

echo "Export job completed successfully (${export_count} files)"
