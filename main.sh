#!/bin/bash

#==========================
# Prepare Terminal
#==========================
clear
echo "================================"
echo " COLUMBUS JOB SETUP AUTOMATION"
echo "================================"


#==============================================
# Redirect all output to log file
#==============================================
LOG_FILE="log.out"
exec > >(tee -a "$LOG_FILE") 2>&1

#==============================================
# Step 0: Ask for the Columbus directory
#==============================================

echo -e "\n\nSetting up Columbus \n==========================="
while true; do
    read -e -p "Enter Columbus directory: " -i "/usr/local/chem.sw/Columbus" COLUMBUS
    
    # Check if both runc and colinp exist in the directory
    if [ -f "$COLUMBUS/runc" ] && [ -f "$COLUMBUS/colinp" ]; then
        export COLUMBUS
        echo "Columbus directory set to: $COLUMBUS"
        break
    else
        echo "Error: Could not find 'runc' and/or 'colinp' in '$COLUMBUS'"
        echo "Please check the directory path and try again."
    fi
done


#==============================================
# Step 2: Ask for xyz file directory and copy it
#==============================================

echo -e "\n\nSelect .xyz file \n==========================="

cd ./Scripts || { echo "❌ Scripts directory not found!"; exit 1; }

# Check for existing .xyz files in the current directory
xyz_files=(*.xyz)

#if [ -e "${xyz_files[0]}" ]; then
#    echo "Found existing .xyz file(s) in the directory:"
#    select xyz_choice in "${xyz_files[@]}" "Import a new .xyz file"; do
#        if [ "$xyz_choice" = "Import a new .xyz file" ]; then
#            while true; do
#                read -p "Enter the full path to your '.xyz' file: " xyz_path
#                if [ -f "$xyz_path" ]; then
#                    cp "$xyz_path" .
#                    echo "$(basename "$xyz_path") copied to Scripts directory."
#                    break
#                else
#                    echo "File not found at '$xyz_path'. Please try again."
#                fi
#            done
#            break
#        elif [ -n "$xyz_choice" ]; then
#            echo "Using existing file: $xyz_choice"
#            break
#        else
#            echo "Invalid selection. Please try again."
#        fi
#    done
#else
#    # No existing .xyz files, prompt for import
#    while true; do
#       read -p "Enter the full path to your '.xyz' file: " xyz_path
#        if [ -f "$xyz_path" ]; then
#            cp "$xyz_path" .
#            echo "$(basename "$xyz_path") copied to Scripts directory."
#            break
#        else
#            echo "File not found at '$xyz_path'. Please try again."
#        fi
#    done
#fi
#sleep 1
if [ -e "${xyz_files[0]}" ]; then
    echo "Found existing .xyz file(s) in the directory:"
    select xyz_choice in "${xyz_files[@]}" "Import a new .xyz file"; do
        if [ "$xyz_choice" = "Import a new .xyz file" ]; then
            while true; do
                read -p "Enter the full path to your '.xyz' file: " xyz_path
                if [ -f "$xyz_path" ]; then
                    cp "$xyz_path" .
                    selected_xyz_file="$(basename "$xyz_path")"
                    echo "$selected_xyz_file copied to Scripts directory."
                    break
                else
                    echo "File not found at '$xyz_path'. Please try again."
                fi
            done
            break
        elif [ -n "$xyz_choice" ]; then
            echo "Using existing file: $xyz_choice"
            selected_xyz_file="$xyz_choice"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
else
    while true; do
        read -p "Enter the full path to your '.xyz' file: " xyz_path
        if [ -f "$xyz_path" ]; then
            cp "$xyz_path" .
            selected_xyz_file="$(basename "$xyz_path")"
            echo "$selected_xyz_file copied to Scripts directory."
            break
        else
            echo "File not found at '$xyz_path'. Please try again."
        fi
    done
fi
sleep 1


#==============================================
# Step 2.5: Convert the xyz file to a geom
#==============================================
if [ ! -f "./make_geom.sh" ]; then
    echo "[$(date)] ERROR: File not found - ./make_geom.sh" >> error.log
    exit 1
elif [ ! -x "./make_geom.sh" ]; then
    echo "[$(date)] ERROR: File not executable - ./make_geom.sh" >> error.log
    exit 1
else
    # ./part_i-make_geom.sh 2>> error.log
    ./make_geom.sh "$selected_xyz_file" "$COLUMBUS" 2>> error.log
    if [ $? -ne 0 ]; then
        echo "[$(date)] ERROR: Script exited with error code $?" >> error.log
    fi
fi

#==============================================
# Step 1: Go to Scripts directory and run input.sh
#==============================================

echo -e "\n\nProvide parameters for Columbus job \n==========================="

# Check if input_values.txt exists
if [ -f input_values.txt ]; then
    echo "⚙️  input_values.txt already exists."
    read -p "Do you want to use the existing values? (y/n): " use_existing

    if [[ "$use_existing" =~ ^[Yy]$ ]]; then
        echo "✅ Using existing input_values.txt..."
    else
        echo "🔁 Running input.sh to create new input values..."
        if [ -f input.sh ]; then
            bash input.sh
        else
            echo "❌ input.sh not found in Scripts directory!"
            exit 1
        fi
    fi
else
    echo "🆕 input_values.txt not found. Running input.sh..."
    if [ -f input.sh ]; then
        bash input.sh
    else
        echo "❌ input.sh not found in Scripts directory!"
        exit 1
    fi
fi

# Write the columbus directory to input_values
echo "set COLUMBUS $COLUMBUS" >> input_values.txt


#==============================================
# Step 1.25: Choose what to run
#==============================================

# Calculation set (cc-pvdz=1, cc-pvtz=6)
echo "Select calculation set:"
echo "1) cc-pvdz"
echo "6) cc-pvtz"
read -p "Enter set number: " calculation_set

echo "Select multiplicity:"
echo "1) Singlet"
#echo "2) Both"
echo "3) Triplet"
read -p "Enter multiplicity number (1 or 3): " singlet_triplet_num

#==============================================
# Step 1.4: Determine variables
#==============================================

# Map calculation set to text label
if [ "$calculation_set" -eq 1 ]; then
    calculation_set_var="DZ"
elif [ "$calculation_set" -eq 6 ]; then
    calculation_set_var="TZ"
else
    echo "❌ Invalid calculation set number!"
    exit 1
fi

# Define multiplicity options based on selection
if [ "$singlet_triplet_num" -eq 1 ]; then
    multiplicities=("Singlet")
elif [ "$singlet_triplet_num" -eq 3 ]; then
    multiplicities=("Triplet")
elif [ "$singlet_triplet_num" -eq 2 ]; then
    multiplicities=("Singlet" "Triplet")
else
    echo "❌ Invalid multiplicity number!"
    exit 1
fi

#==============================================
# Step 1.45: Choose Run Mode (Parallel or Serial)
#==============================================

echo ""
echo "=============================================="
echo "  ⚙️  Run Mode Selection"
echo "=============================================="
read -p "Do you want to run in parallel mode? (y/n): " run_parallel

if [[ "$run_parallel" =~ ^[Yy]$ ]]; then
    echo ""
    echo "🧮 Enter parallel configuration values:"

    read -p "Number of cores (ncores) [default 4]: " ncores
    ncores=${ncores:-4}

    read -p "Memory per core in MB (mem_per_core) [default 750]: " mem_per_core
    mem_per_core=${mem_per_core:-750}

    read -p "Effective bandwidth (bandwidth) [default 50]: " bandwidth
    bandwidth=${bandwidth:-50}

    read -p "Processors per node (processor_per_node) [default 4]: " processor_per_node
    processor_per_node=${processor_per_node:-4}

    read -p "Core memory in MB (core_memory) [default 20000]: " core_memory
    core_memory=${core_memory:-20000}

    echo ""
    echo "✅ Parallel configuration collected."

    # Append to input_values.txt so that later sections inherit these values
    {
        echo ""
        echo "#=============================================="
        echo "# Parallel Configuration"
        echo "#=============================================="
        #echo "set run_mode parallel"
        echo "set ncores $ncores"
        echo "set mem_per_core $mem_per_core"
        echo "set bandwidth $bandwidth"
        echo "set processor_per_node $processor_per_node"
        echo "set core_memory $core_memory"
    } >> input_values.txt
else
    echo "🧩 Running in serial mode (default configuration)."
    #echo "set run_mode serial" >> input_values.txt
fi


#==============================================
# Step 1.475: Uses Slurm File or Not
#==============================================

# Ask if the user wants to use Slurm
while true; do
    read -p "Do you want to submit the job via Slurm? (y/n): " use_slurm
    case "$use_slurm" in
        [Yy]* ) 
            use_slurm="yes"
            echo ""
            echo "Before providing your Slurm file, please ensure the following:"
            echo "0) Make sure the file is on the cluster/workstation you are currently using."
            echo "1) Make sure your email is correct in the Slurm file."
            echo "2) Make sure the number of cores and memory requested is appropriate."
            echo "3) Other Slurm parameters are set correctly."
            echo ""
	    slurm_path=""
            # Prompt for full path until valid file is provided
            while true; do
                read -p "Enter the full path to your Slurm file: " slurm_path
                if [ -f "$slurm_path" ]; then
                    cp "$slurm_path" ./columbus.slurm
                    echo "Slurm file copied to current directory as 'columbus.slurm'."
                    break
                else
                    echo "File not found at '$slurm_path'. Please try again."
                fi
            done
            break
            ;;
        [Nn]* )
            use_slurm="no"
            break
            ;;
        * )
            echo "Please answer y or n."
            ;;
    esac
done

echo ""
echo "Slurm submission: $use_slurm"



#==============================================
# Step 1.5: Custom Input Values (per multiplicity)
#==============================================

for singlet_triplet_var in "${multiplicities[@]}"; do
    echo ""
    echo "=============================================="
    echo "  🧩 Custom Input Values for $singlet_triplet_var State"
    echo "=============================================="

    # Ask user for job options
    read -p "Do you want to run MCSCF for $singlet_triplet_var? (y/n): " run_mcscf
    read -p "Do you want to run CISD for $singlet_triplet_var? (y/n): " run_cisd
    read -p "Do you want to run AQCC for $singlet_triplet_var? (y/n): " run_aqcc

    
     # Determine high spin for this state
    if [ "$singlet_triplet_var" == "Singlet" ]; then
        high_spin="no"
        run_mcscf_singlet=$run_mcscf
        run_cisd_singlet=$run_cisd
        run_aqcc_singlet=$run_aqcc
    else
        high_spin="yes"
        run_mcscf_triplet=$run_mcscf
        run_cisd_triplet=$run_cisd
        run_aqcc_triplet=$run_aqcc
    fi


    # --- MCSCF ---
    if [[ "$run_mcscf" =~ ^[Yy]$ ]]; then
        read -p "Enter MCSCF number of iterations for $singlet_triplet_var: " mcscf_iter
        mcscf_iter=${mcscf_iter:-"-1"}
        read -p "Enter MCSCF number of optimization cycles for $singlet_triplet_var: " mcscf_opt_iter
        mcscf_opt_iter=${mcscf_opt_iter:-"-1"}
        read -p "Allocate memory (in MB) for this job: " mcscf_mem
        mcscf_mem=${mcscf_mem:-"4000"}
        
    else
        mcscf_iter="-1"
        mcscf_opt_iter="-1"
        mcscf_mem="4000"
    fi

    # --- CISD ---
    if [[ "$run_cisd" =~ ^[Yy]$ ]]; then
        read -p "Enter CISD number of iterations for $singlet_triplet_var: " cisd_iter
        cisd_iter=${cisd_iter:-"-1"}
        read -p "Enter CISD number of optimization cycles for $singlet_triplet_var: " cisd_opt_iter
        cisd_opt_iter=${cisd_opt_iter:-"-1"}
        read -p "Allocate memory (in MB) for this job: " cisd_mem
        cisd_mem=${cisd_mem:-"4000"}
    else
        cisd_iter="-1"
        cisd_opt_iter="-1"
        cisd_mem="4000"
    fi

    # --- AQCC ---
    if [[ "$run_aqcc" =~ ^[Yy]$ ]]; then
        read -p "Enter AQCC number of iterations for $singlet_triplet_var: " aqcc_iter
        aqcc_iter=${aqcc_iter:-"-1"}
        read -p "Enter AQCC number of optimization cycles for $singlet_triplet_var: " aqcc_opt_iter
        aqcc_opt_iter=${aqcc_opt_iter:-"-1"}
        read -p "Allocate memory (in MB) for this job: " aqcc_mem
        aqcc_mem=${aqcc_mem:-"4000"}
    else
        aqcc_iter="-1"
        aqcc_opt_iter="-1"
        aqcc_mem="4000"
    fi
    
    if [ "$singlet_triplet_var" == "Singlet" ]; then
        mcscf_mem_singlet=$mcscf_mem
        cisd_mem_singlet=$cisd_mem
        aqcc_mem_singlet=$aqcc_mem
    else
    	mcscf_mem_triplet=$mcscf_mem
    	cisd_mem_triplet=$cisd_mem
    	aqcc_mem_triplet=$aqcc_mem
    fi

    OUTPUT_DIR="../Columbus/$calculation_set_var/$singlet_triplet_var"
    OUTPUT_FILE="$OUTPUT_DIR/input_values.txt"

    mkdir -p "$OUTPUT_DIR"

    {
        cat input_values.txt
        echo ""
        echo "# CUSTOM INPUT ($singlet_triplet_var)"
        echo "#==========================="
        echo "set calculation_set $calculation_set"
        echo "set singlet_triplet_num $singlet_triplet_num"
        echo "set high_spin $high_spin"
        echo "set mcscf_iter $mcscf_iter"
        echo "set mcscf_opt_iter $mcscf_opt_iter"
        echo "set cisd_iter $cisd_iter"
        echo "set cisd_opt_iter $cisd_opt_iter"
        echo "set aqcc_iter $aqcc_iter"
        echo "set aqcc_opt_iter $aqcc_opt_iter"
    } > "$OUTPUT_FILE"

    echo "✅ Created $OUTPUT_FILE for $singlet_triplet_var (high_spin=$high_spin)"
done

echo ""
echo "🎉 Setup complete. Input values stored successfully for all selected multiplicities."



#==============================================
# Step 1.6: Running the necessary jobs
#==============================================
# Start both runs (as needed) and track PIDs

CONFIG_FILE="config.txt"

# write all parameters for run.sh
cat <<EOF > "$CONFIG_FILE"
calculation_set=$calculation_set
run_parallel=$run_parallel
use_slurm=$use_slurm
slurm_path=$slurm_path

# Singlet settings
run_mcscf_singlet=${run_mcscf_singlet:-no}
run_cisd_singlet=${run_cisd_singlet:-no}
run_aqcc_singlet=${run_aqcc_singlet:-no}

mcscf_mem_singlet=${mcscf_mem_singlet:-4000}
cisd_mem_singlet=${cisd_mem_singlet:-4000}
aqcc_mem_singlet=${aqcc_mem_singlet:-4000}

# Triplet settings
run_mcscf_triplet=${run_mcscf_triplet:-no}
run_cisd_triplet=${run_cisd_triplet:-no}
run_aqcc_triplet=${run_aqcc_triplet:-no}

mcscf_mem_triplet=${mcscf_mem_triplet:-4000}
cisd_mem_triplet=${cisd_mem_triplet:-4000}
aqcc_mem_triplet=${aqcc_mem_triplet:-4000}

COLUMBUS=$COLUMBUS
EOF

# now launch runs:
for multiplicity in "${multiplicities[@]}"; do
    echo "➡️ Starting $multiplicity run..."
    ./run.sh "$multiplicity" &
    pid=$!
    echo "PID ($multiplicity): $pid"
done




#for singlet_triplet_var in "${multiplicities[@]}"; do
#    if [ "$singlet_triplet_var" == "Singlet" ]; then
#        echo "➡️ Starting Singlet run..."
#        ./run.sh "$calculation_set" 1 "$run_mcscf_singlet" "$run_cisd_singlet" "$run_aqcc_singlet" "$run_parallel" "$mcscf_mem_singlet" "$cisd_mem_singlet" "$aqcc_mem_singlet" "$COLUMBUS"&
#        singlet_pid=$!
#        echo "🧬 Singlet PID: $singlet_pid"
#    elif [ "$singlet_triplet_var" == "Triplet" ]; then
#        echo "➡️ Starting Triplet run..."
#        ./run.sh "$calculation_set" 3 "$run_mcscf_triplet" "$run_cisd_triplet" "$run_aqcc_triplet" "$run_parallel" "$mcscf_mem_triplet" "$cisd_mem_triplet" "$aqcc_mem_triplet" "$COLUMBUS"&
#        triplet_pid=$!
#        echo "⚛️ Triplet PID: $triplet_pid"
#    fi
#done

# Wait for completion and log status
if [ -n "$singlet_pid" ]; then
    wait "$singlet_pid"
    echo "✅ Singlet run (PID $singlet_pid) completed at $(date)."
fi

if [ -n "$triplet_pid" ]; then
    wait "$triplet_pid"
    echo "✅ Triplet run (PID $triplet_pid) completed at $(date)."
fi

echo "🎉 All selected runs completed successfully."


