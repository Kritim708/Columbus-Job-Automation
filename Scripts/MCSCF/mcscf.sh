#!/bin/bash

set -euo pipefail

WORK_DIR="$PWD"
MCSCF_DIR="$WORK_DIR/../MCSCF"
SCRIPTS_DIR=""
if [ -f "$WORK_DIR/config.txt" ]; then
    SCRIPTS_DIR="$(awk 'index($0, "SCRIPTS_DIR=") == 1 { sub(/\r$/, ""); print substr($0, 13); exit }' "$WORK_DIR/config.txt")"
fi


usage() {
    cat <<EOF
Usage:
  $(basename "$0") -create_files [options]
  $(basename "$0") -run_job [directory]
  $(basename "$0") -clear_files

-create_files : Verifies input_values.txt, mcscf.exp, and geom are
                present, then runs mcscf.exp to prepare the MCSCF
                Columbus input files in this directory.
-run_job      : Copies files into the given directory and starts runc
                there. Defaults to ../MCSCF relative to this script.
-clear_files  : Removes everything this script generated, keeping only
                mcscf.sh, mcscf.exp, input_values.txt, and geom.
-check_convergence  : Checks the convergence of the MCSCF calculation if it exists.
Options for -create_files:
  -mcscf-iter N
  -mcscf-opt-iter N
  -core-memory N    Override the MCSCF memory value (default: input_values.txt)
EOF
}

validate_integer() {
    local name="$1"
    local value="$2"

    [[ "$value" == "-1" || "$value" =~ ^[0-9]+$ ]] \
        || fail "$name must be -1 or a non-negative integer."
}

fail() { echo "Error: $*" >&2; exit 1; }
require_value() {
    [ "$#" -ge 2 ] && [ -n "$2" ] || fail "$1 requires a value."
}

mcscf_iter=""
mcscf_opt_iter=""
core_memory=""
core_memory_set=0
run_job_path=""

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
        -check_convergence)
            [ -z "$action" ] || fail "Only one action may be specified."
            action="check_convergence"
            shift
            ;;
        -run_job)
            [ -z "$action" ] || fail "Only one action may be specified."
            action="run_job"
            shift
            if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
                run_job_path="$1"
                shift
            fi
            ;;

        -mcscf-iter)
            require_value "$1" "${2-}"
            mcscf_iter="$2"
            shift 2
            ;;

        -mcscf-opt-iter)
            require_value "$1" "${2-}"
            mcscf_opt_iter="$2"
            shift 2
            ;;

        -core-memory)
            require_value "$1" "${2-}"
            core_memory="$2"
            core_memory_set=1
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

[ -z "$mcscf_iter" ]     || validate_integer "-mcscf-iter" "$mcscf_iter"
[ -z "$mcscf_opt_iter" ] || validate_integer "-mcscf-opt-iter" "$mcscf_opt_iter"
if [ "$core_memory_set" -eq 1 ]; then
    [[ "$core_memory" =~ ^[0-9]+$ ]] \
        || fail "-core-memory must be a non-negative integer."
fi

set_input_value() {
    local key="$1"
    local value="$2"
    grep -q "^set $key " "$WORK_DIR/input_values.txt" \
        || fail "Missing key '$key' in input_values.txt"
    sed -i "s/^set $key .*/set $key $value/" "$WORK_DIR/input_values.txt"
}

load_core_memory() {
    core_memory="$(awk '
        $1 == "set" && $2 == "mcscf_mem" {
            print $3
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$WORK_DIR/input_values.txt")" \
        || fail "Missing key 'mcscf_mem' in input_values.txt"
    [[ "$core_memory" =~ ^[0-9]+$ ]] \
        || fail "Value for 'mcscf_mem' in input_values.txt must be a non-negative integer."
}


create_files() {
    local required=(input_values.txt mcscf.exp geom)
    local f
    for f in "${required[@]}"; do
        [ -f "$WORK_DIR/$f" ] || fail "Missing required file: $f"
    done

    if [ "$core_memory_set" -eq 1 ]; then
        set_input_value mcscf_mem "$core_memory"
    else
        load_core_memory
    fi

    if [ -n "$mcscf_iter" ]; then
        set_input_value mcscf_iter "$mcscf_iter"
    fi

    if [ -n "$mcscf_opt_iter" ]; then
        set_input_value mcscf_opt_iter "$mcscf_opt_iter"
    fi
    command -v expect >/dev/null 2>&1 || fail "'expect' is not installed."
    (cd "$WORK_DIR" && expect ./mcscf.exp)
    # print_next_commands
    printf 'Use ./mcscf.sh -run_job path-to-directory to perform the calculations.\n' 

}

print_next_commands() {
    local columbus quoted_columbus
    [ -f "$WORK_DIR/config.txt" ] || fail "Missing config.txt; cannot determine COLUMBUS."
    columbus="$(awk 'index($0, "COLUMBUS=") == 1 { sub(/\r$/, ""); print substr($0, 10); exit }' "$WORK_DIR/config.txt")"
    [ -n "$columbus" ] || fail "COLUMBUS is missing from config.txt."
    printf -v quoted_columbus '%q' "$columbus"

    printf '\nNow run the following commands:\n'
    printf 'COLUMBUS=%s\n' "$quoted_columbus"
    printf 'cp * ../MCSCF/.\n'
    printf 'cd ../MCSCF\n'
    printf '%s/runc -m %s > runls &\n' "$quoted_columbus" "$core_memory"
}

run_job() {
    local target_path target_dir work_dir_real columbus response
    local -a files

    [ -f "$WORK_DIR/input_values.txt" ] \
        || fail "Missing required file: input_values.txt"
    load_core_memory

    [ -f "$WORK_DIR/config.txt" ] || fail "Missing config.txt; cannot determine COLUMBUS."
    columbus="$(awk 'index($0, "COLUMBUS=") == 1 { sub(/\r$/, ""); print substr($0, 10); exit }' "$WORK_DIR/config.txt")"
    [ -n "$columbus" ] || fail "COLUMBUS is missing from config.txt."
    [ -x "$columbus/runc" ] || fail "COLUMBUS runc is missing or not executable: $columbus/runc"

    if [ -n "$run_job_path" ]; then
        target_path="$run_job_path"
    else
        target_path="$MCSCF_DIR/."
    fi
    [ -d "$target_path" ] || fail "Run directory does not exist: $target_path"
    [ -w "$target_path" ] || fail "Run directory is not writable: $target_path"
    
    target_dir="$(cd -- "$target_path" && pwd -P)" \
        || fail "Cannot access run directory: $target_path"
    work_dir_real="$(cd -- "$WORK_DIR" && pwd -P)"

    # Check if source and destination are the same directory
    if [ "$target_dir" = "$work_dir_real" ]; then
        printf 'Warning: WORK_DIR and target_dir are the eact same folder (%s). \n' "$target_dir"
        read -r -p "Do you want to continue? (y/n) " response
        case "$response" in
            [yY][eE][sS]|[yY])
                ;;
            *)
                fail "Operation cancelled by user."
                ;;
        esac
    else 
        # Only copy if they are different directories
        shopt -s nullglob
        files=("$WORK_DIR"/*)
        shopt -u nullglob
        [ "${#files[@]}" -gt 0 ] || fail "No files to copy from $WORK_DIR."
        \cp -R -f -- "${files[@]}" "$target_dir/" \
            || fail "Failed to copy files to $target_dir."
    fi

    (
        local job_status
        cd -- "$target_dir"
        if "$columbus/runc" -m "$core_memory" > runls; then
            job_status=0
        else
            job_status=$?
        fi

        if [ "$target_dir" != "$work_dir_real" ]; then
            shopt -s nullglob
            files=("$target_dir"/*)
            shopt -u nullglob
            if [ "${#files[@]}" -gt 0 ]; then
                cp -R -- "${files[@]}" "$MCSCF_DIR/" \
                    || { echo "Error: Failed to copy job files back to $MCSCF_DIR." >&2; exit 1; }
            fi
        fi

        if [ "$job_status" -eq 0 ]; then
            printf 'Job completed; copied results back to %s.\n' "$MCSCF_DIR"
        else
            printf 'Job exited with status %s; copied results back to %s.\n' \
                "$job_status" "$MCSCF_DIR" >&2
        fi
        exit "$job_status"
    ) &
    printf 'Started Columbus job in %s (PID %s); results will be copied back to %s when it finishes.\n' \
        "$target_dir" "$!" "$MCSCF_DIR"
}


clear_files() {
    local keep=("mcscf.sh" "mcscf.exp" "input_values.txt" "geom" "config.txt")
    local remove_list=()
    local f base skip k

    shopt -s nullglob 

    for f in "$WORK_DIR"/*; do
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

check_convergence() {
    python3 "$SCRIPTS_DIR/check_convergence/main.py" mcscf "$WORK_DIR" \
        || fail "Convergence check failed."
}

case "$action" in
    create)
        create_files
        ;;
    clear)
        [ "$core_memory_set" -eq 0 ] \
            || fail "-core-memory can only be used with -create_files."
        clear_files
        ;;
    check_convergence)
        [ "$core_memory_set" -eq 0 ] \
            || fail "-core-memory can only be used with -create_files."
        check_convergence
        ;;
    run_job)
        [ "$core_memory_set" -eq 0 ] \
            || fail "-core-memory can only be used with -create_files."
        run_job
        ;;
    *)
        [ "$core_memory_set" -eq 0 ] \
            || fail "-core-memory can only be used with -create_files."
        usage
        exit 2
        ;;
esac