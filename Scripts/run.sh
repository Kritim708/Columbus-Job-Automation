#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"
BASE_INPUT="$SCRIPT_DIR/input_values.txt"

usage() {
    cat <<EOF
Usage:
    $(basename "$0") -mcscf|-cisd-ser|-cisd-par|-aqcc-ser|-aqcc-par \
        -singlet|-triplet -dz|-tz [-m MB] [-nproc COUNT] [optional values]

This command prepares Columbus input files only. It never runs runc or Slurm.
Defaults: memory=4000, iterations=-1, optimization_cycles=-1,
parallel cores=4, memory per core=750, bandwidth=50, processors per node=4,
core memory=20000. Optional flags: -mcscf-iter, -mcscf-opt-iter,
-cisd-iter, -cisd-opt-iter, -aqcc-iter, -aqcc-opt-iter, -mem-per-core,
-bandwidth, -ppn, and -core-memory.
EOF
}

fail() {
    echo "Error: $*" >&2
    exit 2
}

require_value() {
    [ "$#" -ge 2 ] || fail "$1 requires a value."
}

[ -f "$BASE_INPUT" ] || fail "Run './main.sh initialize' first; Scripts/input_values.txt is missing."

stage=""
spin_name=""
basis=""
memory=4000
nproc=4
mcscf_iter=-1
mcscf_opt_iter=-1
cisd_iter=-1
cisd_opt_iter=-1
aqcc_iter=-1
aqcc_opt_iter=-1
mem_per_core=750
bandwidth=50
processor_per_node=4
core_memory=20000

while [ "$#" -gt 0 ]; do
    case "$1" in
        -mcscf) stage="MCSCF"; shift ;;
        -cisd-ser) stage="CISD"; run_mode="ser"; shift ;;
        -cisd-par) stage="CISD"; run_mode="par"; shift ;;
        -aqcc-ser) stage="AQCC"; run_mode="ser"; shift ;;
        -aqcc-par) stage="AQCC"; run_mode="par"; shift ;;
        -singlet) spin_name="Singlet"; shift ;;
        -triplet) spin_name="Triplet"; shift ;;
        -dz) basis="DZ"; calculation_set=1; shift ;;
        -tz) basis="TZ"; calculation_set=6; shift ;;
        -m)
            [ "$#" -ge 2 ] || fail "-m requires a value."
            memory="$2"
            shift 2
            ;;
        -nproc)
            [ "$#" -ge 2 ] || fail "-nproc requires a value."
            nproc="$2"
            shift 2
            ;;
        -mcscf-iter) require_value "$1" "$@"; mcscf_iter="$2"; shift 2 ;;
        -mcscf-opt-iter) require_value "$1" "$@"; mcscf_opt_iter="$2"; shift 2 ;;
        -cisd-iter) require_value "$1" "$@"; cisd_iter="$2"; shift 2 ;;
        -cisd-opt-iter) require_value "$1" "$@"; cisd_opt_iter="$2"; shift 2 ;;
        -aqcc-iter) require_value "$1" "$@"; aqcc_iter="$2"; shift 2 ;;
        -aqcc-opt-iter) require_value "$1" "$@"; aqcc_opt_iter="$2"; shift 2 ;;
        -mem-per-core) require_value "$1" "$@"; mem_per_core="$2"; shift 2 ;;
        -bandwidth) require_value "$1" "$@"; bandwidth="$2"; shift 2 ;;
        -ppn) require_value "$1" "$@"; processor_per_node="$2"; shift 2 ;;
        -core-memory) require_value "$1" "$@"; core_memory="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option '$1'." ;;
    esac
done

[ -n "$stage" ] || fail "Choose one stage option."
[ -n "$spin_name" ] || fail "Choose -singlet or -triplet."
[ -n "$basis" ] || fail "Choose -dz or -tz."
[ "$stage" = "MCSCF" ] && run_mode="ser"
[[ "$memory" =~ ^[0-9]+$ ]] || fail "Memory must be a non-negative integer."
[[ "$nproc" =~ ^[1-9][0-9]*$ ]] || fail "-nproc must be a positive integer."

if [ -f "$CONFIG_FILE" ]; then
    COLUMBUS="$(awk -F= '/^COLUMBUS=/ { sub(/\r$/, "", $2); print $2; exit }' "$CONFIG_FILE")"
fi
[ -n "${COLUMBUS:-}" ] || fail "COLUMBUS is not configured; run './main.sh initialize'."

source_input="$ROOT_DIR/Columbus/$basis/$spin_name/input_values.txt"
if [ -f "$source_input" ]; then
    base_input="$source_input"
else
    base_input="$BASE_INPUT"
fi

prep_dir="$ROOT_DIR/Columbus/$basis/$spin_name/$stage-prep"
mkdir -p "$prep_dir"
rm -f "$prep_dir"/*
cp "$SCRIPT_DIR/geom" "$prep_dir/"
cp "$base_input" "$prep_dir/input_values.base.txt"

if [ "$spin_name" = "Singlet" ]; then
    singlet_triplet_num=1
    high_spin=no
    spatial_symmetry=$(
        awk '$2=="singlet_spatial_symmetry" {print $3; exit}' "$base_input"
    )
else
    singlet_triplet_num=3
    high_spin=yes
    spatial_symmetry=$(
        awk '$2=="triplet_spatial_symmetry" {print $3; exit}' "$base_input"
    )
fi

[ -n "$spatial_symmetry" ] || fail "Could not determine spatial symmetry from $base_input."

input_file="$prep_dir/input_values.txt"
{
    cat "$base_input"
    echo ""
    echo "# Generated preparation values"
    echo "set COLUMBUS \"$COLUMBUS\""
    echo "set calculation_set $calculation_set"
    echo "set singlet_triplet_num $singlet_triplet_num"
    echo "set spatial_symmetry $spatial_symmetry"
    echo "set high_spin $high_spin"
    echo "set mcscf_iter $mcscf_iter"
    echo "set mcscf_opt_iter $mcscf_opt_iter"
    echo "set cisd_iter $cisd_iter"
    echo "set cisd_opt_iter $cisd_opt_iter"
    echo "set aqcc_iter $aqcc_iter"
    echo "set aqcc_opt_iter $aqcc_opt_iter"
    echo "set mcscf_mem $memory"
    echo "set cisd_mem $memory"
    echo "set aqcc_mem $memory"
    echo "set ncores $nproc"
    echo "set mem_per_core $mem_per_core"
    echo "set bandwidth $bandwidth"
    echo "set processor_per_node $processor_per_node"
    echo "set core_memory $core_memory"
} > "$input_file"

case "$stage" in
    MCSCF)
        cp "$SCRIPT_DIR/mcscf.exp" "$prep_dir/"
        (cd "$prep_dir" && expect ./mcscf.exp)
        ;;
    CISD)
        [ -d "$ROOT_DIR/Columbus/$basis/$spin_name/MCSCF" ] || fail "MCSCF directory is missing."
        cp "$ROOT_DIR/Columbus/$basis/$spin_name/MCSCF/*" "$prep_dir/."
        cp "$input_file" "$prep_dir/input_values.txt"
        cp "$SCRIPT_DIR/cisd-$run_mode.exp" "$prep_dir/"
        (cd "$prep_dir" && expect "./cisd-$run_mode.exp")
        ;;
    AQCC)
        [ -d "$ROOT_DIR/Columbus/$basis/$spin_name/CISD" ] || fail "CISD directory is missing."
        cp  "$ROOT_DIR/Columbus/$basis/$spin_name/CISD/*" "$prep_dir/."
        cp "$input_file" "$prep_dir/input_values.txt"
        cp "$SCRIPT_DIR/aqcc-$run_mode.exp" "$prep_dir/"
        (cd "$prep_dir" && expect "./aqcc-$run_mode.exp")
        ;;
esac

echo "Input files prepared in $prep_dir"
# echo "No Columbus calculation was started."