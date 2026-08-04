#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"
BASE_INPUT="$SCRIPT_DIR/input_values.txt"
COLUMBUS_ROOT="$ROOT_DIR/Columbus"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [options]

Scaffolds mcscf.sh / cisd.sh / aqcc.sh, their .exp files, geom, and a
ready-to-use input_values.txt into every MCSCF-prep, CISD-prep, and
AQCC-prep directory under Columbus/<basis>/<diradical>/<spin>/.

This script never runs runc, expect, or Slurm; it only stages files.
After running it, go into a *-prep directory and use e.g.:
    ./mcscf.sh -create_files
    ./cisd.sh -ser -create_files    (or -par)
    ./aqcc.sh -par -create_files    (or -ser)

Optional filters (default: all found under Columbus/):
  -basis DZ|TZ
  -diradical NAME
  -spin singlet|triplet

Optional global values (applied to every generated input_values.txt):
  -m MB              memory (default 4000)
  -nproc COUNT       parallel cores (default 4)
  -mcscf-iter N       (default -1)
  -mcscf-opt-iter N   (default -1)
  -cisd-iter N        (default -1)
  -cisd-opt-iter N    (default -1)
  -aqcc-iter N        (default -1)
  -aqcc-opt-iter N    (default -1)
  -mem-per-core N    (default 750)
  -bandwidth N       (default 50)
  -ppn N             (default 4)
  -core-memory N     (default 20000)

Per-diradical/basis/spin overrides:
  Place a file at Columbus/<basis>/<diradical>/<spin>/input_values.txt
  (e.g. with a different singlet_spatial_symmetry) and it will be used
  as the base instead of Scripts/input_values.txt for that combination.
EOF
}

fail() { echo "Error: $*" >&2; exit 2; }
require_value() { [ "$#" -ge 2 ] || fail "$1 requires a value."; }

[ -f "$BASE_INPUT" ] || fail "Run '../main.sh initialize' first; Scripts/input_values.txt is missing."
[ -d "$COLUMBUS_ROOT" ] || fail "Columbus directory not found; run '../main.sh initialize' first."
[ -f "$SCRIPT_DIR/geom" ] || fail "Scripts/geom is missing; run '../main.sh initialize' first."

filter_basis=""
filter_diradical=""
filter_spin=""
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
        -basis) require_value "$1" "$@"; filter_basis="$2"; shift 2 ;;
        -diradical) require_value "$1" "$@"; filter_diradical="$2"; shift 2 ;;
        -spin) require_value "$1" "$@"; filter_spin="$2"; shift 2 ;;
        -m) require_value "$1" "$@"; memory="$2"; shift 2 ;;
        -nproc) require_value "$1" "$@"; nproc="$2"; shift 2 ;;
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

[[ "$memory" =~ ^[0-9]+$ ]] || fail "Memory must be a non-negative integer."
[[ "$nproc" =~ ^[1-9][0-9]*$ ]] || fail "-nproc must be a positive integer."

if [ -n "$filter_basis" ]; then
    filter_basis="$(echo "$filter_basis" | tr '[:lower:]' '[:upper:]')"
    [[ "$filter_basis" == "DZ" || "$filter_basis" == "TZ" ]] || fail "-basis must be DZ or TZ."
fi
if [ -n "$filter_spin" ]; then
    case "$(echo "$filter_spin" | tr '[:upper:]' '[:lower:]')" in
        singlet) filter_spin="Singlet" ;;
        triplet) filter_spin="Triplet" ;;
        *) fail "-spin must be singlet or triplet." ;;
    esac
fi

if [ -f "$CONFIG_FILE" ]; then
    COLUMBUS="$(awk -F= '/^COLUMBUS=/ { sub(/\r$/, "", $2); print $2; exit }' "$CONFIG_FILE")"
fi
[ -n "${COLUMBUS:-}" ] || fail "COLUMBUS is not configured; run '../main.sh initialize'."

for tmpl in mcscf.sh cisd.sh aqcc.sh mcscf.exp cisd-ser.exp cisd-par.exp aqcc-ser.exp aqcc-par.exp; do
    [ -f "$SCRIPT_DIR/$tmpl" ] || fail "Missing template file Scripts/$tmpl."
done

prepared_count=0

# Stages one *-prep directory: writes input_values.txt and copies the
# stage script + .exp file(s) + geom into it. Returns 1 (without failing
# the whole run) if spatial symmetry can't be determined for this combo.
stage_prep_dir() {
    local prep_dir="$1" stage="$2"
    local basis="$3" diradical="$4" spin_name="$5" base_input="$6"

    local calculation_set singlet_triplet_num high_spin spatial_symmetry
    [ "$basis" = "DZ" ] && calculation_set=1 || calculation_set=6
    if [ "$spin_name" = "Singlet" ]; then
        singlet_triplet_num=1
        high_spin=no
        spatial_symmetry=$(awk '$2=="singlet_spatial_symmetry" {print $3; exit}' "$base_input")
    else
        singlet_triplet_num=3
        high_spin=yes
        spatial_symmetry=$(awk '$2=="triplet_spatial_symmetry" {print $3; exit}' "$base_input")
    fi

    if [ -z "$spatial_symmetry" ]; then
        echo "Warning: no spatial symmetry found for $basis/$diradical/$spin_name (looked in $base_input); skipping $stage-prep." >&2
        return 1
    fi

    mkdir -p "$prep_dir"
    rm -f "$prep_dir"/*
    cp "$SCRIPT_DIR/geom" "$prep_dir/"

    {
        cat "$base_input"
        echo ""
        echo "# Generated by run.sh"
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
    } > "$prep_dir/input_values.txt"

    case "$stage" in
        MCSCF)
            cp "$SCRIPT_DIR/mcscf.sh" "$SCRIPT_DIR/mcscf.exp" "$prep_dir/"
            chmod +x "$prep_dir/mcscf.sh"
            ;;
        CISD)
            cp "$SCRIPT_DIR/cisd.sh" "$SCRIPT_DIR/cisd-ser.exp" "$SCRIPT_DIR/cisd-par.exp" "$prep_dir/"
            chmod +x "$prep_dir/cisd.sh"
            ;;
        AQCC)
            cp "$SCRIPT_DIR/aqcc.sh" "$SCRIPT_DIR/aqcc-ser.exp" "$SCRIPT_DIR/aqcc-par.exp" "$prep_dir/"
            chmod +x "$prep_dir/aqcc.sh"
            ;;
    esac

    return 0
}

for basis_dir in "$COLUMBUS_ROOT"/*/; do
    [ -d "$basis_dir" ] || continue
    basis="$(basename "$basis_dir")"
    [[ "$basis" == "DZ" || "$basis" == "TZ" ]] || continue
    [ -n "$filter_basis" ] && [ "$basis" != "$filter_basis" ] && continue

    for diradical_dir in "$basis_dir"*/; do
        [ -d "$diradical_dir" ] || continue
        diradical="$(basename "$diradical_dir")"
        [ -n "$filter_diradical" ] && [ "$diradical" != "$filter_diradical" ] && continue

        for spin_name in Singlet Triplet; do
            [ -n "$filter_spin" ] && [ "$spin_name" != "$filter_spin" ] && continue
            spin_dir="${diradical_dir}${spin_name}"
            [ -d "$spin_dir" ] || continue

            override_input="$spin_dir/input_values.txt"
            if [ -f "$override_input" ]; then
                base_input="$override_input"
            else
                base_input="$BASE_INPUT"
            fi

            for stage in MCSCF CISD AQCC; do
                prep_dir="$spin_dir/$stage-prep"
                if [ ! -d "$prep_dir" ]; then
                    echo "Warning: $prep_dir missing; skipping (was Columbus initialized?)." >&2
                    continue
                fi
                if stage_prep_dir "$prep_dir" "$stage" "$basis" "$diradical" "$spin_name" "$base_input"; then
                    prepared_count=$((prepared_count + 1))
                fi
            done
        done
    done
done

[ "$prepared_count" -gt 0 ] || fail "No prep directories were prepared. Check spatial symmetry settings and directory structure."

echo "Prepared $prepared_count stage directories."
echo "Next: cd into a *-prep directory and run e.g. ./mcscf.sh -create_files"