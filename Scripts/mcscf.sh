#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") -create_files [options]
  $(basename "$0") -clear_files

-create_files : Verifies input_values.txt, mcscf.exp, and geom are
                present, then runs mcscf.exp to prepare the MCSCF
                Columbus input files in this directory.
-clear_files  : Removes everything this script generated, keeping only
                mcscf.sh, mcscf.exp, input_values.txt, and geom.
Options for -create_files:
  -mcscf-iter N
  -mcscf-opt-iter N
EOF
}

fail() { echo "Error: $*" >&2; exit 1; }
require_value() {
    [ "$#" -ge 2 ] || fail "$1 requires a value."
    [[ "$2" != -* ]] || fail "$1 requires a value."
}

mcscf_iter=""
mcscf_opt_iter=""

action=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -create_files)
            [ -z "$action" ] || fail "Only one action may be specified."
            action="create"
            shift
            ;;

        -clear_files)
            [ -z "$action" ] || fail "Only one action may be specified."
            action="clear"
            shift
            ;;

        -mcscf-iter)
            require_value "$1" "$@"
            mcscf_iter="$2"
            shift 2
            ;;

        -mcscf-opt-iter)
            require_value "$1" "$@"
            mcscf_opt_iter="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            fail "Unknown option '$1'"
            ;;
    esac
done

if [ -n "$mcscf_iter" ]; then
    [[ "$mcscf_iter" =~ ^[0-9]+$ ]] \
        || fail "-mcscf-iter must be an integer."
fi

if [ -n "$mcscf_opt_iter" ]; then
    [[ "$mcscf_opt_iter" =~ ^[0-9]+$ ]] \
        || fail "-mcscf-opt-iter must be an integer."
fi

set_input_value() {
    local key="$1"
    local value="$2"
    sed -i "s/^set $key .*/set $key $value/" "$SCRIPT_DIR/input_values.txt"
}



create_files() {
    local required=(input_values.txt mcscf.exp geom)
    local f
    for f in "${required[@]}"; do
        [ -f "$SCRIPT_DIR/$f" ] || fail "Missing required file: $f"
    done
    if [ -n "$mcscf_iter" ]; then
        set_input_value mcscf_iter "$mcscf_iter"
    fi

    if [ -n "$mcscf_opt_iter" ]; then
        set_input_value mcscf_opt_iter "$mcscf_opt_iter"
    fi
    command -v expect >/dev/null 2>&1 || fail "'expect' is not installed."
    (cd "$SCRIPT_DIR" && expect ./mcscf.exp)
}

clear_files() {
    local keep=("mcscf.sh" "mcscf.exp" "input_values.txt" "geom")
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

case "$action" in
    create)
        create_files
        ;;
    clear)
        clear_files
        ;;
    *)
        usage
        exit 2
        ;;
esac