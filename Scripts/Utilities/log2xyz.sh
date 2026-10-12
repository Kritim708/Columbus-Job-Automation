#!/bin/bash
# Converts a Gaussian optimization .log file to an xyz file for make_geom.sh
#
# Usage: make_xyz.sh <log_file> <output_name> [unique_centers]
#   log_file        Gaussian .log file (path as given, or relative to ../ of this script)
#   output_name     name of the xyz file to create (.xyz is added if missing)
#   unique_centers  optional comma-separated Gaussian center numbers of the unique
#                   atoms, e.g. 1,2,3,4,9. If omitted, ALL atoms are written.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "ERROR: $*" >&2; exit 1; }

LOG_FILE="$1"
OUT_NAME="$2"
UNIQUE="$3"
OUTPUT_DIR="${4:-$SCRIPT_DIR/..}"

[ -n "$LOG_FILE" ] || fail "No log file provided."
[ -n "$OUT_NAME" ] || fail "No output name provided."

# Resolve the log file: as given, otherwise relative to the parent of the script dir
if [ -f "$LOG_FILE" ]; then
    FULL_LOG="$LOG_FILE"
elif [ -f "$SCRIPT_DIR/../$LOG_FILE" ]; then
    FULL_LOG="$SCRIPT_DIR/../$LOG_FILE"
else
    fail "Log file not found: $LOG_FILE"
fi

# Output goes next to where xyz2geom.sh looks for its input (../) by default.
[[ "$OUT_NAME" == *.xyz ]] || OUT_NAME="$OUT_NAME.xyz"
mkdir -p "$OUTPUT_DIR"
OUT_FILE="$OUTPUT_DIR/$OUT_NAME"

# Line number of the LAST "Stationary point found"
last="$(grep -n "Stationary point found" "$FULL_LOG" | tail -n 1 | cut -d: -f1)"
[ -n "$last" ] || fail "'Stationary point found' not in $FULL_LOG (did the optimization converge?)."

tail -n +"$last" "$FULL_LOG" | awk -v sel="$UNIQUE" '
BEGIN {
    split("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr", sym, " ")
    if (sel != "") {
        m = split(sel, s, ",")
        for (i = 1; i <= m; i++) want[s[i]] = 1
    }
    state = 0; done = 0; n = 0
}
done { next }
state == 0 && /Standard orientation:/ { state = 1; dashes = 0; next }
state >= 1 && /^ *-+ *$/ {
    dashes++
    if (dashes == 2) state = 2          # table body starts after 2nd dashed line
    else if (dashes == 3) done = 1      # table ends at 3rd dashed line
    next
}
state == 2 && NF >= 5 {
    c = $1; z = $2
    if (sel != "" && !(c in want)) next
    if (!(z in sym)) { print "ERROR: unsupported atomic number " z > "/dev/stderr"; bad = 1; next }
    n++
    el[n] = sym[z]; x[n] = $(NF-2); y[n] = $(NF-1); zz[n] = $NF
}
END {
    if (bad || n == 0) exit 1
    print n
    print ""
    # heavy atoms first, hydrogens last
    for (i = 1; i <= n; i++) if (el[i] != "H") printf "%-2s %15.10f %15.10f %15.10f\n", el[i], x[i], y[i], zz[i]
    for (i = 1; i <= n; i++) if (el[i] == "H") printf "%-2s %15.10f %15.10f %15.10f\n", el[i], x[i], y[i], zz[i]
}' > "$OUT_FILE"

if [ $? -ne 0 ] || [ ! -s "$OUT_FILE" ]; then
    rm -f "$OUT_FILE"
    fail "Could not extract Standard orientation coordinates from $FULL_LOG."
fi

echo "Wrote $(head -n 1 "$OUT_FILE") atoms to $OUT_FILE"
[ -n "$UNIQUE" ] || echo "NOTE: no unique centers given, so ALL atoms were written. Rerun with e.g. 1,2,3,4,9 to keep only unique atoms."