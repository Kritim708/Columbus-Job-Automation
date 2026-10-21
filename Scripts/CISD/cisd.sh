#!/bin/bash

set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCSCF_DIR="$WORK_DIR/../MCSCF"
CISD_DIR="$WORK_DIR/../CISD"
SCRIPTS_DIR=""
if [ -f "$WORK_DIR/config.txt" ]; then
    SCRIPTS_DIR="$(awk 'index($0, "SCRIPTS_DIR=") == 1 { sub(/\r$/, ""); print substr($0, 13); exit }' "$WORK_DIR/config.txt")"
fi




usage() {
    cat <<EOF
Usage:
  $(basename "$0") -ser|-par -create_files
  $(basename "$0") -ser|-par -run_job [directory]
  $(basename "$0") -create_slurm [MEMORY_MB]
  $(basename "$0") -clear_files

-ser / -par    : Run CISD serially or in parallel (required with
                 -create_files or -run_job).
-create_files  : Verifies input_values.txt, cisd-<mode>.exp, and geom
                 are present, checks that ../MCSCF has completed output,
                 copies that output in, then runs cisd-<mode>.exp.
-run_job       : Copies files into the given directory and starts runc
                 there. Defaults to ../CISD relative to this script.
-clear_files   : Removes everything this script generated, keeping only
                 cisd.sh, cisd-ser.exp, cisd-par.exp, input_values.txt,
                 and geom.
-create_slurm  : Creates parallelSpydurColumbus722.slurm in the current
                 directory using its partitioned_*cpu_*bw_*mb.dat file.
                 Prompts for a mail address. Optional MEMORY_MB must be
                 greater than the file's calculated memory requirement.

                 Options for -create_files:
  -cisd-iter N       : Set maximum CISD iterations (default: -1).
  -cisd-opt-iter N   : Set CISD optimization iterations (default: -1).

Parallel-only options (valid only with -par):
  -ncores COUNT       : Number of parallel cores (default: 4).
  -mem-per-core N    : Memory per core (default: 750).
  -processor_per_node N             : Override the default processor_per_node value (which follows -ncores).
  -core-memory N     : Legacy option; set to -ncores x -mem-per-core.

Examples:
  $(basename "$0") -ser -create_files
  $(basename "$0") -ser -create_files -cisd-iter 100
  $(basename "$0") -par -create_files -cisd-iter 100 -ncores 16 -mem-per-core 2500
  $(basename "$0") -par -run_job
EOF
}

fail() { echo "Error: $*" >&2; exit 1; }
require_value() {
    [ "$#" -ge 2 ] || fail "$1 requires a value."
}

validate_integer() {
    local name="$1"
    local value="$2"

    [[ "$value" == "-1" || "$value" =~ ^[0-9]+$ ]] \
        || fail "$name must be -1 or a non-negative integer."
}

check_convergence() {
    python3 "$SCRIPTS_DIR/check_convergence/main.py" cisd "$WORK_DIR" \
        || fail "Convergence check failed."
}

set_input_value() {
    local key="$1"
    local value="$2"

    grep -q "^set $key " "$WORK_DIR/input_values.txt" \
        || fail "Missing key '$key' in input_values.txt"

    sed -i "s/^set $key .*/set $key $value/" \
        "$WORK_DIR/input_values.txt"
}


create_files() {
    local mode="$1"
    local required=(input_values.txt "cisd-$mode.exp" )
    local f
    for f in "${required[@]}"; do
        [ -f "$WORK_DIR/$f" ] || fail "Missing required file: $f"
    done

    [ -d "$MCSCF_DIR" ] || fail "MCSCF directory not found at $MCSCF_DIR."

    local mcscf_files=()
    local f
    shopt -s nullglob
    for f in "$MCSCF_DIR"/*; do
        [ -f "$f" ] || continue

        filename="${f##*/}"

        # Skip files that should not be copied
        [[ "$filename" == "input_values.txt" ]] && continue
        [[ "$filename" == *.exp ]] && continue
        [[ "$filename" == *.sh ]] && continue

        mcscf_files+=("$f")
    done
    shopt -u nullglob

    [ "${#mcscf_files[@]}" -gt 0 ] \
        || fail "MCSCF directory has no files. Run mcscf.sh -create_files and complete the MCSCF calculation first."

    [ -f "$MCSCF_DIR/GEOMS/geom.min" ] || fail "MCSCF job has not converged yet."

    cp -- "${mcscf_files[@]}" "$WORK_DIR/"
    cp $MCSCF_DIR/MOCOEFS/mocoef_mc.sp "$WORK_DIR/mocoef"

    if [ -n "$cisd_iter" ]; then
        set_input_value cisd_iter "$cisd_iter"
    fi

    if [ -n "$cisd_opt_iter" ]; then
        set_input_value cisd_opt_iter "$cisd_opt_iter"
    fi

    if [ "$mode" = "par" ]; then
        if [ "$processor_per_node_explicit" -eq 0 ]; then
            processor_per_node="$ncores"
        fi
        core_memory=$((ncores * mem_per_core))
        set_input_value ncores "$ncores"
        set_input_value mem_per_core "$mem_per_core"
        set_input_value processor_per_node "$processor_per_node"
        set_input_value core_memory "$core_memory"
    fi

    command -v expect >/dev/null 2>&1 || fail "'expect' is not installed."
    (cd "$WORK_DIR" && expect "./cisd-$mode.exp")
    # print_next_commands "$mode"
    printf 'Use ./cisd.sh -run_job -%s path-to-directory to perform the calculations.\n' "$mode"
}

print_next_commands() {
    local mode="$1"
    local columbus quoted_columbus
    [ -f "$WORK_DIR/config.txt" ] || fail "Missing config.txt; cannot determine COLUMBUS."
    columbus="$(awk 'index($0, "COLUMBUS=") == 1 { sub(/\r$/, ""); print substr($0, 10); exit }' "$WORK_DIR/config.txt")"
    [ -n "$columbus" ] || fail "COLUMBUS is missing from config.txt."
    printf -v quoted_columbus '%q' "$columbus"

    printf '\nNow run the following commands:\n'
    printf 'COLUMBUS=%s\n' "$quoted_columbus"
    printf 'cp * ../CISD/.\n'
    printf 'cd ../CISD\n'
    if [ "$mode" = "par" ]; then
        printf '%s/runc -m %s -nproc %s > runls &\n' \
            "$quoted_columbus" "$core_memory" "$ncores"
    else
        printf '%s/runc -m %s > runls &\n' \
            "$quoted_columbus" "$core_memory"
    fi
}

read_input_integer() {
    local key="$1"
    local value
    value="$(awk -v key="$key" '
        $1 == "set" && $2 == key {
            print $3
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$WORK_DIR/input_values.txt")" \
        || fail "Missing key '$key' in input_values.txt"
    [[ "$value" =~ ^[0-9]+$ ]] \
        || fail "Value for '$key' in input_values.txt must be a non-negative integer."
    printf '%s' "$value"
}

run_job() {
    local target_path target_dir work_dir_real columbus job_memory job_ncores response
    local -a files

    [ -n "$mode" ] || fail "Specify -ser or -par together with -run_job."
    [ -f "$WORK_DIR/input_values.txt" ] \
        || fail "Missing required file: input_values.txt"
    [ -f "$WORK_DIR/config.txt" ] || fail "Missing config.txt; cannot determine COLUMBUS."
    columbus="$(awk 'index($0, "COLUMBUS=") == 1 { sub(/\r$/, ""); print substr($0, 10); exit }' "$WORK_DIR/config.txt")"
    [ -n "$columbus" ] || fail "COLUMBUS is missing from config.txt."
    [ -x "$columbus/runc" ] || fail "COLUMBUS runc is missing or not executable: $columbus/runc"

    job_memory="$core_memory"
    if [ "$mode" = "par" ]; then
        job_memory="$(read_input_integer core_memory)"
        job_ncores="$(read_input_integer ncores)"
        [ "$job_ncores" -gt 0 ] \
            || fail "Value for 'ncores' in input_values.txt must be a positive integer."
    fi

    if [ -n "$run_job_path" ]; then
        target_path="$run_job_path"
    else
        target_path="$CISD_DIR/."
    fi
    [ -d "$target_path" ] || fail "Run directory does not exist: $target_path"
    [ -w "$target_path" ] || fail "Run directory is not writable: $target_path"
    target_dir="$(cd -- "$target_path" && pwd -P)" \
        || fail "Cannot access run directory: $target_path"
    work_dir_real="$(cd -- "$WORK_DIR" && pwd -P)"
    
    # Check if the source and destination are the same directory
    if [ "$target_dir" = "$work_dir_real" ]; then
        printf 'Warning: WORK_DIR and target_dir are the exact same folder (%s). \n' "$target_dir"
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
        cp -R -- "${files[@]}" "$target_dir/"
    fi


    (
        local job_status
        cd -- "$target_dir"

        # Load the module in the same subshell environment before running the tool
        module load columbus/722 || { echo "Error: Failed to load module columbus/722" >&2; exit 1; }

        if [ "$mode" = "par" ]; then
            if "$columbus/runc" -m "$job_memory" -nproc "$job_ncores" > runls; then
                job_status=0
            else
                job_status=$?
            fi
        elif "$columbus/runc" -m "$job_memory" > runls; then
            job_status=0
        else
            job_status=$?
        fi

        # Only copy back files if target_dir and CISD_DIR are different
        if [ "$target_dir" != "$CISD_DIR" ]; then
            shopt -s nullglob
            files=("$target_dir"/*)
            shopt -u nullglob
            if [ "${#files[@]}" -gt 0 ]; then
                cp -R -- "${files[@]}" "$CISD_DIR/" \
                    || { echo "Error: Failed to copy job files back to $CISD_DIR." >&2; exit 1; }
            fi
        fi

        if [ "$job_status" -eq 0 ]; then
            printf 'Job completed; copied results back to %s.\n' "$CISD_DIR"
        else
            printf 'Job exited with status %s; copied results back to %s.\n' \
                "$job_status" "$CISD_DIR" >&2
        fi
        exit "$job_status"
    ) &
    printf 'Started %s CISD job in %s (PID %s); results will be copied back to %s when it finishes.\n' \
        "$mode" "$target_dir" "$!" "$CISD_DIR"
}


clear_files() {
    local keep=("cisd.sh" "cisd-ser.exp" "cisd-par.exp" "input_values.txt" "geom" "config.txt")
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

create_slurm() {
    local template email="" data_file data_name
    local cpu_count memory_per_cpu required_memory total_memory
    local slurm_memory memory_per_process temp_file
    local -a candidates=() matches=()

    [ -n "$SCRIPTS_DIR" ] \
        || fail "SCRIPTS_DIR is missing from $WORK_DIR/config.txt."
    template="$SCRIPTS_DIR/parallelSpydurColumbus722.slurm"
    [ -f "$template" ] || fail "Slurm template not found: $template"
    [ -r "$template" ] || fail "Slurm template is not readable: $template"

    read -r -p "Enter email address for Slurm notifications (leave empty to keep the template value): " email

    shopt -s nullglob
    candidates=("$WORK_DIR"/partitioned_*cpu_*bw_*mb.dat)
    shopt -u nullglob
    for data_file in "${candidates[@]}"; do
        data_name="${data_file##*/}"
        if [[ "$data_name" =~ ^partitioned_([0-9]+)cpu_[0-9]+bw_([0-9]+)mb\.dat$ ]]; then
            matches+=("$data_file")
        fi
    done
    [ "${#matches[@]}" -eq 1 ] \
        || fail "Expected exactly one partitioned_<CPUs>cpu_<bandwidth>bw_<MEMORY>mb.dat file in $WORK_DIR; found ${#matches[@]}."

    data_name="${matches[0]##*/}"
    [[ "$data_name" =~ ^partitioned_([0-9]+)cpu_[0-9]+bw_([0-9]+)mb\.dat$ ]] \
        || fail "Could not extract CPU and memory values from $data_name."
    cpu_count=$((10#${BASH_REMATCH[1]}))
    memory_per_cpu=$((10#${BASH_REMATCH[2]}))
    [ "$cpu_count" -gt 0 ] || fail "CPU count in $data_name must be positive."
    [ "$memory_per_cpu" -gt 0 ] || fail "Memory value in $data_name must be positive."
    required_memory=$((cpu_count * memory_per_cpu))

    if [ -n "$create_slurm_memory" ]; then
        [[ "$create_slurm_memory" =~ ^[0-9]+$ ]] \
            || fail "Optional Slurm memory must be a positive integer in MB."
        total_memory=$((10#$create_slurm_memory))
        [ "$total_memory" -gt "$required_memory" ] \
            || fail "Slurm memory must be greater than the calculated requirement of ${required_memory} MB."
    else
        total_memory="$required_memory"
    fi
    slurm_memory="$total_memory"
    memory_per_process=$((total_memory / cpu_count))

    if [ -n "$email" ] && [[ "$email" == *$'\n'* || "$email" == *$'\r'* ]]; then
        fail "Email address must not contain newline characters."
    fi
    temp_file="$(mktemp "$WORK_DIR/.parallelSpydurColumbus722.slurm.XXXXXX")" \
        || fail "Could not create a temporary Slurm file in $WORK_DIR."
    if ! SLURM_EMAIL="$email" \
        SLURM_MEMORY="$slurm_memory" \
        SLURM_CPUS="$cpu_count" \
        SLURM_MEMORY_PER_PROCESS="$memory_per_process" \
        awk '
            /^#SBATCH --mail-user=/ {
                mail_count++
                if (ENVIRON["SLURM_EMAIL"] != "") {
                    print "#SBATCH --mail-user=" ENVIRON["SLURM_EMAIL"]
                    next
                }
                print
                next
            }
            /^#SBATCH --mem=/ {
                mem_count++
                print "#SBATCH --mem=" ENVIRON["SLURM_MEMORY"] "M"
                next
            }
            /^#SBATCH --cpus-per-task=/ {
                cpu_count++
                print "#SBATCH --cpus-per-task=" ENVIRON["SLURM_CPUS"]
                next
            }
            /^TOTAL_MEM=/ {
                total_count++
                print "TOTAL_MEM=" ENVIRON["SLURM_MEMORY"] "      # Total memory in MB (equal to SBATCH --mem)"
                next
            }
            /^MEM_PER_PROC=/ {
                process_count++
                print "MEM_PER_PROC=" ENVIRON["SLURM_MEMORY_PER_PROCESS"] "    # Memory per process in MB (number given by colinp + some padding)"
                next
            }
            { print }
            END {
                if (mail_count != 1 || mem_count != 1 || cpu_count != 1 ||
                    total_count != 1 || process_count != 1) {
                    print "Error: Slurm template must contain exactly one each of the mail, memory, CPU, TOTAL_MEM, and MEM_PER_PROC settings." > "/dev/stderr"
                    exit 1
                }
            }
        ' "$template" > "$temp_file"; then
        rm -f -- "$temp_file"
        fail "Could not generate Slurm file from $template."
    fi

    mv -- "$temp_file" "$WORK_DIR/parallelSpydurColumbus722.slurm" \
        || { rm -f -- "$temp_file"; fail "Could not save Slurm file in $WORK_DIR."; }
    printf 'Created %s/parallelSpydurColumbus722.slurm (CPUs: %s, memory: %s MB, memory per process: %s MB).\n' \
        "$WORK_DIR" "$cpu_count" "$total_memory" "$memory_per_process"
}

mode=""
action=""
run_job_path=""
create_slurm_memory=""

ncores=4
cisd_iter=""
cisd_opt_iter=""
mem_per_core=750

processor_per_node=4
processor_per_node_explicit=0
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

        -run_job)
            action="run_job"
            shift
            if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
                run_job_path="$1"
                shift
            fi
            ;;

        -clear_files)
            action="clear"
            shift
            ;;

        -create_slurm)
            action="create_slurm"
            shift
            if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
                create_slurm_memory="$1"
                shift
            fi
            ;;

        -check_convergence)
            action="check_convergence"
            shift
            ;;

        -ncores)
            require_value "$1" "$@"
            ncores="$2"
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

        -processor_per_node)
            require_value "$1" "$@"
            processor_per_node="$2"
            processor_per_node_explicit=1
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
[[ "$ncores" =~ ^[1-9][0-9]*$ ]] \
    || fail "-ncores must be a positive integer."
[[ "$mem_per_core" =~ ^[1-9][0-9]*$ ]] \
    || fail "-mem-per-core must be a positive integer."
validate_integer "-processor_per_node" "$processor_per_node"
validate_integer "-core-memory" "$core_memory"

[ -z "$cisd_iter" ]     || validate_integer "-cisd-iter" "$cisd_iter"
[ -z "$cisd_opt_iter" ] || validate_integer "-cisd-opt-iter" "$cisd_opt_iter"

if [ "$mode" = "ser" ]; then
    if [ "$ncores" -ne 4 ] || \
       [ "$mem_per_core" -ne 750 ] || \
       [ "$processor_per_node" -ne 4 ] || \
       [ "$core_memory" -ne 20000 ]; then
        fail "-ncores, -mem-per-core, -processor_per_node, and -core-memory are only valid with -par."
    fi
fi

case "$action" in
    create)
        [ -n "$mode" ] || fail "Specify -ser or -par together with -create_files."
        create_files "$mode"
        ;;
    run_job)
        run_job
        ;;
    clear)
        clear_files
        ;;
    create_slurm)
        create_slurm
        ;;
    check_convergence)
        check_convergence
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac