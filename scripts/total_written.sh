#!/usr/bin/env bash
# total_written.sh — total disk data written (and read) across cycles.
#
# Sums MaxDiskWrite (col 4) and MaxDiskRead (col 5) from the diskreport PSV
# files. Prints a per-cycle breakdown and a grand total.
#
# Usage:
#   ./total_written.sh                          # all logs/sacct_io_*.psv
#   ./total_written.sh logs/sacct_io_202605*.psv # a subset
set -uo pipefail

files=( "$@" )
if [[ ${#files[@]} -eq 0 ]]; then
    files=( logs/sacct_io_*.psv sacct_io_*.psv )
fi
real=(); for f in "${files[@]}"; do [[ -f "$f" ]] && real+=("$f"); done
[[ ${#real[@]} -eq 0 ]] && { echo "no sacct_io_*.psv files found" >&2; exit 1; }

awk -F'|' '
# parse a value that is plain bytes, or bytes with a K/M/G/T/P suffix (1024-based)
function tobytes(v,   u,mult){
    if (v ~ /^[0-9]+(\.[0-9]+)?$/) return v+0
    if (v ~ /^[0-9]+(\.[0-9]+)?[KMGTP]$/){
        u=substr(v,length(v),1)
        mult=(u=="K")?1024:(u=="M")?1048576:(u=="G")?1073741824:(u=="T")?1099511627776:1125899906842624
        return (v+0)*mult
    }
    return 0
}
{
    if (!(FILENAME in seen)){ seen[FILENAME]=1; order[++k]=FILENAME }
    w=tobytes($4); r=tobytes($5)
    fw[FILENAME]+=w; fr[FILENAME]+=r
    tw+=w; tr+=r
}
END{
    printf "%-34s %12s %12s\n", "cycle", "write_GiB", "read_GiB"
    for (i=1;i<=k;i++){ f=order[i]; n=f; sub(/.*\//,"",n)
        printf "%-34s %12.3f %12.3f\n", n, fw[f]/1073741824, fr[f]/1073741824 }
    printf "%-34s %12.3f %12.3f\n", "----", tw/1073741824, tr/1073741824
    printf "\nTOTAL written: %.0f bytes  (%.2f MiB, %.3f GiB)\n", tw, tw/1048576, tw/1073741824
    printf "TOTAL read   : %.0f bytes  (%.2f MiB, %.3f GiB)\n", tr, tr/1048576, tr/1073741824
    printf "Cycles: %d\n", k
}
' "${real[@]}"
