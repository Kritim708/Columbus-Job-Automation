#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCSCF_DIR="$SCRIPT_DIR/../MCSCF"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") -ser|-par -create_files
  $(basename "$0") -clear_files

-ser / -par    : Run CISD serially or in parallel (required with
                 -create_files).
-create_files  : Verifies input_values.txt, cisd-<mode>.exp, and geom
                 are present, checks that ../MCSCF has completed output,
                 copies that output in, then runs cisd-<mode>.exp.
-clear_files   : Removes everything this script generated, keeping only
                 cisd.sh, cisd-ser.exp, cisd-par.exp, input_values.txt,
                 and geom.
EOF
}

fail() { echo "Error: $*" >&2; exit 1; }
require_value() {
    [ "$#" -ge 2 ] || fail "$1 requires a value."
}

validate_integer() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[0-9]+$ ]] \
        || fail "$name must be a non-negative integer."
}
set_input_value() {
    local key="$1"
    local value="$2"

    grep -q "^set $key " "$SCRIPT_DIR/input_values.txt" \
        || fail "Missing key '$key' in input_values.txt"

    sed -i "s/^set $key .*/set $key $value/" \
        "$SCRIPT_DIR/input_values.txt"
}


create_files() {
    local mode="$1"
    local required=(input_values.txt "cisd-$mode.exp" )
    local f
    for f in "${required[@]}"; do
        [ -f "$SCRIPT_DIR/$f" ] || fail "Missing required file: $f"
    done

    if [ -n "$cisd_iter" ]; then
        set_input_value cisd_iter "$cisd_iter"
    fi

    if [ -n "$cisd_opt_iter" ]; then
        set_input_value cisd_opt_iter "$cisd_opt_iter"
    fi

    [ -d "$MCSCF_DIR" ] || fail "MCSCF directory not found at $MCSCF_DIR."
    [ -f "$MCSCF_DIR/GEOMS/geom.min" ] || fail "MCSCF job has not converged yet."
    shopt -s nullglob
    local mcscf_files=("$MCSCF_DIR"/*)
    shopt -u nullglob
    [ "${#mcscf_files[@]}" -gt 0 ] || fail "MCSCF directory is empty. Run mcscf.sh -create_files and complete the MCSCF calculation first."

    cp "${mcscf_files[@]}" "$SCRIPT_DIR/"
    command -v expect >/dev/null 2>&1 || fail "'expect' is not installed."
    (cd "$SCRIPT_DIR" && expect "./cisd-$mode.exp")
}

clear_files() {
    local keep=("cisd.sh" "cisd-ser.exp" "cisd-par.exp" "input_values.txt" )
    local remove_list=()
    local f base skip k
    shopt -s nullglob 
    for f in "$SCRIPT_DIR"/*; do
        base="$(basename "$f")"
        skip=0

        for k in "${keep[@]}"; do
            if [ "$base" = "$k" ]; then
                skip=1
                break
            fi
        done

        if [ "$skip" -eq 0 ]; then
            remove_list+=("$f")
        fi
    done

    shopt -u nullglob 

    if [ "${#remove_list[@]}" -eq 0 ]; then
        echo "No generated files to clear."
        return 0
    fi

    echo "The following files/directories will be removed:"
    printf '  %s\n' "${remove_list[@]}"

    read -r -p "Continue? [y/N] " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Clear operation cancelled."
        return 0
    fi

    for f in "${remove_list[@]}"; do
        rm -rf -- "$f"
    done

    echo "Cleared generated files; kept: ${keep[*]}"
}

mode=""
action=""

nproc=4
cisd_iter=""
cisd_opt_iter=""
mem_per_core=750

ppn=4
core_memory=20000

while [ "$#" -gt 0 ]; do
    case "$1" in
        -ser)
            mode="ser"
            shift
            ;;

        -par)
            mode="par"
            shift
            ;;

        -create_files)
            action="create"
            shift
            ;;

        -clear_files)
            action="clear"
            shift
            ;;

        -nproc)
            require_value "$1" "$@"
            nproc="$2"
            shift 2
            ;;

        -cisd-iter)
            require_value "$1" "$@"
            cisd_iter="$2"
            shift 2
            ;;

        -cisd-opt-iter)
            require_value "$1" "$@"
            cisd_opt_iter="$2"
            shift 2
            ;;

        -mem-per-core)
            require_value "$1" "$@"
            mem_per_core="$2"
            shift 2
            ;;

        -ppn)
            require_value "$1" "$@"
            ppn="$2"
            shift 2
            ;;

        -core-memory)
            require_value "$1" "$@"
            core_memory="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            fail "Unknown option '$1'."
            ;;
    esac
done
validate_integer "-nproc" "$nproc"
validate_integer "-cisd-iter" "$cisd_iter"
validate_integer "-cisd-opt-iter" "$cisd_opt_iter"
validate_integer "-mem-per-core" "$mem_per_core"
validate_integer "-ppn" "$ppn"
validate_integer "-core-memory" "$core_memory"

if [ "$mode" = "ser" ]; then
    if [ "$nproc" -ne 4 ] || \
       [ "$mem_per_core" -ne 750 ] || \
       [ "$ppn" -ne 4 ] || \
       [ "$core_memory" -ne 20000 ]; then
        fail "-nproc, -mem-per-core, -ppn, and -core-memory are only valid with -par."
    fi
fi

case "$action" in
    create)
        [ -n "$mode" ] || fail "Specify -ser or -par together with -create_files."
        create_files "$mode"
        ;;
    clear)
        clear_files
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac