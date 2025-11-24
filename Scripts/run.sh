#!/bin/bash

#==============================================
# Step 0: Import parameters
#==============================================

multiplicity=$1   # "Singlet" or "Triplet"
CONFIG_FILE="config.txt"

# Load config file as shell variables
source "$CONFIG_FILE"

# Select parameters depending on multiplicity
if [ "$multiplicity" = "Singlet" ]; then
    spin=1
    run_mcscf=$run_mcscf_singlet
    run_cisd=$run_cisd_singlet
    run_aqcc=$run_aqcc_singlet
    mcscf_mem=$mcscf_mem_singlet
    cisd_mem=$cisd_mem_singlet
    aqcc_mem=$aqcc_mem_singlet

elif [ "$multiplicity" = "Triplet" ]; then
    spin=3
    run_mcscf=$run_mcscf_triplet
    run_cisd=$run_cisd_triplet
    run_aqcc=$run_aqcc_triplet
    mcscf_mem=$mcscf_mem_triplet
    cisd_mem=$cisd_mem_triplet
    aqcc_mem=$aqcc_mem_triplet
else
    echo "Error: multiplicity must be Singlet or Triplet"
    exit 1
fi

echo "Running $multiplicity"
echo "Run MCSCF: $run_mcscf"
echo "Run CISD:  $run_cisd"
echo "Run AQCC:  $run_aqcc"
echo "Mem MCSCF: $mcscf_mem"
echo "Mem CISD:  $cisd_mem"
echo "Mem AQCC:  $aqcc_mem"


#==============================================
# Step 1: Determine Calculation Set
#==============================================

if [ "$calculation_set" -eq 1 ]; then
    calculation_set_var="DZ"
elif [ "$calculation_set" -eq 6 ]; then
    calculation_set_var="TZ"
else
    calculation_set_var="Unknown"
fi

if [[ "$run_parallel" =~ ^[Yy]$ ]]; then
    run_mode="par"
else
    run_mode="ser"
fi

#==============================================
# Step 2: Redirect all output to log file
#==============================================
LOG_FILE="../Columbus/$calculation_set_var/$multiplicity/log.out"
exec > >(tee -a "$LOG_FILE") 2>&1

#==============================================
# Step 3: Go back one directory
#==============================================
cd .. || exit 1

#==============================================
# Step 4–9: MCSCF stage (conditional)
#==============================================
if [[ "$run_mcscf" =~ ^[Yy]$ ]]; then
    echo "➡️ Starting MCSCF stage..."
    
    mkdir -p ./Columbus/$calculation_set_var/$multiplicity/MCSCF
    cp ./Columbus/$calculation_set_var/$multiplicity/input_values.txt ./Columbus/$calculation_set_var/$multiplicity/MCSCF/
    cp ./Scripts/mcscf.exp ./Columbus/$calculation_set_var/$multiplicity/MCSCF/
    cp ./Scripts/geom ./Columbus/$calculation_set_var/$multiplicity/MCSCF/
    if [ "$use_slurm" = "yes" ]; then
        cp ./Scripts/columbus.slurm ./Columbus/$calculation_set_var/$multiplicity/MCSCF/
    fi


    cd ./Columbus/$calculation_set_var/$multiplicity/MCSCF || { echo "MCSCF directory not found!"; exit 1; }

    # module load columbus/722
    if [ -f mcscf.exp ]; then
        echo "Running mcscf.exp..."
        expect ./mcscf.exp
    else
        echo "❌ mcscf.exp not found!"
        exit 1
    fi

    echo "Running Columbus runc..."
    if [ "$use_slurm" != "yes" ]; then
        $COLUMBUS/runc -m $mcscf_mem > runls &
        runc_pid=$!
        echo "runc PID: $runc_pid"
        wait $runc_pid
        echo "runc finished."
    else
        # Submit the Slurm job and wait until it completes
        slurm_job_id=$(sbatch ./columbus.slurm | awk '{print $4}')
        echo "Slurm job submitted with Job ID: $slurm_job_id"

        # Wait for the Slurm job to finish
        while true; do
            job_state=$(squeue -j $slurm_job_id -h -o "%T")
            if [ -z "$job_state" ]; then
                # Job no longer in queue, assumed finished
                break
            fi
            sleep 5  # check every 5 seconds
        done

        echo "Slurm job $slurm_job_id finished."
    fi


    cp MOCOEFS/mocoef_mc.sp mocoef
    cd ../../../..
else
    echo "⏩ Skipping MCSCF stage."
fi

#==============================================
# Step 10–15: CISD stage (conditional)
#==============================================
if [[ "$run_cisd" =~ ^[Yy]$ ]]; then
    echo "➡️ Starting CISD stage..."

    cd ./Columbus/$calculation_set_var/$multiplicity/ || exit 1
    mkdir -p CI
    cp ./input_values.txt ./CI/
    cp ./MCSCF/* ./CI/
    cp ../../../Scripts/cisd-$run_mode.exp ./CI/
    if [ "$use_slurm" = "yes" ]; then
        cp ../../../Scripts/columbus.slurm ./Columbus/$calculation_set_var/$multiplicity/CI/
    fi

    cd ./CI || { echo "CI directory not found!"; exit 1; }

    # module load columbus/722
    if [ -f cisd-$run_mode.exp ]; then
        echo "Running cisd-$run_mode.exp..."

        while true; do
            expect ./cisd-$run_mode.exp

            # Check last two lines of runc.error
            if [ -f runc.error ]; then
                last_lines=$(tail -n 2 runc.error)
                if echo "$last_lines" | grep -q "not enough memory" && echo "$last_lines" | grep -q "pscript failed"; then
                    echo "  Memory error detected — rerunning expect script..."
                    sleep 2   # optional short delay before retry
                    continue
                fi
            fi

            # If memory error not detected, break the loop
            break
        done

    else
        echo "❌ cisd-$run_mode.exp not found!"
        exit 1
    fi

    echo "✅ cisd-$run_mode.exp finished successfully"    


    echo "Running Columbus runc..."
    if [ "$use_slurm" != "yes" ]; then
        $COLUMBUS/runc -m $cisd_mem > runls &
        runc_pid=$!
        echo "runc PID: $runc_pid"
        wait $runc_pid
        echo "runc finished."
    else
        # Submit the Slurm job and wait until it completes
        slurm_job_id=$(sbatch ./columbus.slurm | awk '{print $4}')
        echo "Slurm job submitted with Job ID: $slurm_job_id"

        # Wait for the Slurm job to finish
        while true; do
            job_state=$(squeue -j $slurm_job_id -h -o "%T")
            if [ -z "$job_state" ]; then
                # Job no longer in queue, assumed finished
                break
            fi
            sleep 5  # check every 5 seconds
        done

        echo "Slurm job $slurm_job_id finished."
    fi

    cd ../../../..
else
    echo "⏩ Skipping CISD stage."
fi

#==============================================
# Step 16–END: AQCC stage (conditional)
#==============================================

if [[ "$run_aqcc" =~ ^[Yy]$ ]]; then
    echo "➡️ Starting AQCC stage..."

    cd ./Columbus/$calculation_set_var/$multiplicity/ || exit 1
    mkdir -p AQCC
    cp ./input_values.txt ./AQCC/
    cp ./CI/* ./AQCC/
    cp ../../../Scripts/aqcc-$run_mode.exp ./AQCC/
    if [ "$use_slurm" = "yes" ]; then
        cp ../../../Scripts/columbus.slurm ./Columbus/$calculation_set_var/$multiplicity/AQCC/
    fi

    cd ./AQCC || { echo "AQCC directory not found!"; exit 1; }
    echo "Before AQCC Columbus is: $COLUMBUS"
    # module load columbus/722
    echo "Before AQCC Columbus is: $COLUMBUS"
    if [ -f aqcc-$run_mode.exp ]; then
        echo "Running aqcc-$run_mode.exp..."
        
        while true; do
            expect ./aqcc-$run_mode.exp

            # Check last two lines of runc.error
            if [ -f runc.error ]; then
                last_lines=$(tail -n 2 runc.error)
                if echo "$last_lines" | grep -q "not enough memory" && echo "$last_lines" | grep -q "pscript failed"; then
                    echo "⚠️ Memory error detected — rerunning expect script..."
                    sleep 2   # optional short delay before retry
                    continue
                fi
            fi

            # If memory error not detected, break the loop
            break
        done

    else
        echo "❌ aqcc-$run_mode.exp not found!"
        exit 1
    fi

    echo "✅ aqcc-$run_mode.exp finished successfully"


    echo "Running Columbus runc..."
    if [ "$use_slurm" != "yes" ]; then
        $COLUMBUS/runc -m $aqcc_mem > runls &
        runc_pid=$!
        echo "runc PID: $runc_pid"
        wait $runc_pid
        echo "runc finished."
    else
        # Submit the Slurm job and wait until it completes
        slurm_job_id=$(sbatch ./columbus.slurm | awk '{print $4}')
        echo "Slurm job submitted with Job ID: $slurm_job_id"

        # Wait for the Slurm job to finish
        while true; do
            job_state=$(squeue -j $slurm_job_id -h -o "%T")
            if [ -z "$job_state" ]; then
                # Job no longer in queue, assumed finished
                break
            fi
            sleep 5  # check every 5 seconds
        done

        echo "Slurm job $slurm_job_id finished."
    fi


    echo "✅ AQCC stage completed successfully."
else
    echo "⏩ Skipping AQCC stage."
fi

#==============================================
echo "🎉 All selected stages completed successfully."
#==============================================
