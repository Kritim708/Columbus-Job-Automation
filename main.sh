#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/Scripts"
WORKING_DIR="$(pwd -P)"
DEFAULT_COLUMBUS="/usr/local/chem.sw/Columbus"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") initialize
  $(basename "$0") add_diradical [NAME]
    $(basename "$0") remove_diradical [NAME]
    $(basename "$0") -columbus_path PATH

Initialize sets up one or more diradicals. Each diradical's geometry and
DRT-derived input_values.txt are stored under diradicals/<NAME>/ in the
current working directory. Calculation folders are created under Columbus/.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

read_columbus_path() {
    if [ -f "$SCRIPTS_DIR/config.txt" ]; then
        awk 'index($0, "COLUMBUS=") == 1 { sub(/\r$/, ""); print substr($0, 10); exit }' \
            "$SCRIPTS_DIR/config.txt"
    fi
}

set_config_value() {
    local key="$1" value="$2" config_file="$SCRIPTS_DIR/config.txt" temp_file
    mkdir -p "$SCRIPTS_DIR" || die "Could not create Scripts directory."
    temp_file="$(mktemp "$SCRIPTS_DIR/.config.txt.XXXXXX")" || die "Could not create temporary config file."
    if [ -f "$config_file" ]; then
        CONFIG_KEY="$key" CONFIG_VALUE="$value" awk '
            BEGIN { key = ENVIRON["CONFIG_KEY"]; value = ENVIRON["CONFIG_VALUE"] }
            index($0, key "=") == 1 {
                if (!written++) print key "=" value
                next
            }
            { print }
            END { if (!written) print key "=" value }
        ' "$config_file" > "$temp_file" || {
            rm -f -- "$temp_file"
            die "Could not update '$config_file'."
        }
    else
        printf '%s=%s\n' "$key" "$value" > "$temp_file"
    fi
    mv -- "$temp_file" "$config_file" || die "Could not update '$config_file'."
}

validate_columbus_path() {
    local path="$1" file
    for file in runc colinp xyz2col.x; do
        [ -f "$path/$file" ] || die "Could not find '$path/$file'."
    done
}

set_columbus_path() {
    local path="$1"
    validate_columbus_path "$path"
    set_config_value COLUMBUS "$path"
    set_config_value SCRIPTS_DIR "$SCRIPTS_DIR"
    echo "Saved Columbus path in $SCRIPTS_DIR/config.txt."
}

ensure_columbus_path() {
    local path
    path="$(read_columbus_path)"
    if [ -z "$path" ]; then
        read -r -p "Enter Columbus directory [$DEFAULT_COLUMBUS]: " path
        path=${path:-$DEFAULT_COLUMBUS}
        set_columbus_path "$path"
    fi
    validate_columbus_path "$path"
    set_config_value SCRIPTS_DIR "$SCRIPTS_DIR"
    COLUMBUS_PATH="$path"
}

validate_diradical() {
    [[ "$1" =~ ^[a-zA-Z0-9]+_[0-9]+$ ]] || \
        die "Invalid diradical format: $1 (expected molecule_number, e.g. thiazole_24)."
}

# Returns 0 if valid; otherwise prints the reason to stderr and returns 1
check_diradical() {
    local d="$1"
    [[ "$d" == 'q' ]] && return 1
    if [[ ! "$d" =~ ^[a-zA-Z0-9]+_[0-9]+$ ]]; then
        echo "  Invalid format: '$d' (expected molecule_number, e.g. thiazole_24)." >&2
        return 1
    fi
    if [ -e "$WORKING_DIR/diradicals/$d" ]; then
        echo "  '$d' is already initialized." >&2
        return 1
    fi
    return 0
}

prompt_diradicals() {
    local -a entered=()
    local -A seen=()
    local d ok

    while true; do
        read -r -p "Enter the diradicals to prepare (space separated, e.g. thiazole_24 thiazole_25, or q to quit): " -a entered

        ok=1
        seen=()

        if [ "${#entered[@]}" -eq 0 ]; then
            echo "  No diradicals entered. At least one is required." >&2
            ok=0
        else
            for d in "${entered[@]}"; do
                if [ -n "${seen[$d]:-}" ]; then
                    echo "  '$d' was entered more than once." >&2
                    ok=0
                    continue
                fi
                seen[$d]=1
                check_diradical "$d" || ok=0
            done
        fi

        if [ "$ok" -eq 1 ]; then
            diradicals=("${entered[@]}")
            return 0
        fi

    done
}

initialize() {
    local shared_drt="" use_shared_drt answer diradical
    local -a diradicals=()
    local -A seen_diradicals=()

    mkdir -p "$SCRIPTS_DIR" || die "Could not create Scripts directory."
    echo "Columbus input-file setup"
    echo "========================="
    ensure_columbus_path

    prompt_diradicals
    while true; do
        read -r -p "Use the same DRT file for all diradicals? [Y/n]: " answer
        case "${answer,,}" in
            ""|y|yes) use_shared_drt=yes; break ;;
            n|no) use_shared_drt=no; break ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
    if [ "$use_shared_drt" = yes ]; then
        while true; do
            read -r -p "Enter the full path to the shared DRT table (.xlsx): " shared_drt
            [ -f "$shared_drt" ] && break
            echo "File not found: $shared_drt"
        done
    fi


    for diradical in "${diradicals[@]}"; do
        bash "$SCRIPTS_DIR/Utilities/setup_diradical.sh" "$diradical" "$shared_drt" \
            || die "Setup failed for '$diradical'."
    done

    echo "Initialization complete."
    echo "Next run '$SCRIPTS_DIR/run.sh' from '$WORKING_DIR'."
}

add_diradical() {
    local diradical="${1:-}"

    if [ -z "$diradical" ]; then
        read -r -p "Enter diradical name (e.g. thiazole_24): " diradical
    fi
    validate_diradical "$diradical"

    ensure_columbus_path
    bash "$SCRIPTS_DIR/Utilities/setup_diradical.sh" "$diradical" \
        || die "Setup failed for '$diradical'."
    echo "Added $diradical. Next run '$SCRIPTS_DIR/run.sh' from '$WORKING_DIR'."
}

remove_diradical() {
    local diradical="${1:-}" path confirm
    local -a paths=() found=()

    if [ -z "$diradical" ]; then
        read -r -p "Enter diradical name to remove (or q to cancel): " diradical
        case "${diradical,,}" in
            q|quit) echo "Removal cancelled."; return 0 ;;
        esac
    fi
    validate_diradical "$diradical"

    paths=(
        "$WORKING_DIR/diradicals/$diradical"
        "$WORKING_DIR/Columbus/DZ/$diradical"
        "$WORKING_DIR/Columbus/TZ/$diradical"
    )
    for path in "${paths[@]}"; do
        if [ -e "$path" ] || [ -L "$path" ]; then
            found+=("$path")
        fi
    done

    if [ "${#found[@]}" -eq 0 ]; then
        echo "No files or directories found for '$diradical'; nothing removed."
        return 0
    fi

    echo "WARNING: this permanently removes all contents at these paths for '$diradical':"
    printf '  %s\n' "${found[@]}"
    read -r -p "Continue? [y/N] " confirm
    case "${confirm,,}" in
        y|yes) ;;
        *) echo "Removal cancelled; no files were removed."; return 0 ;;
    esac

    for path in "${found[@]}"; do
        rm -rf -- "$path"
    done
    echo "Removed diradical '$diradical'."
}

case "${1:-}" in
    initialize)
        [ "$#" -eq 1 ] || die "initialize does not accept arguments."
        initialize
        ;;
    add_diradical)
        [ "$#" -le 2 ] || die "add_diradical accepts at most one name."
        add_diradical "${2:-}"
        ;;
    remove_diradical)
        [ "$#" -le 2 ] || die "remove_diradical accepts at most one name."
        remove_diradical "${2:-}"
        ;;
    -columbus_path)
        [ "$#" -eq 2 ] || die "Usage: $(basename "$0") -columbus_path PATH"
        set_columbus_path "$2"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac