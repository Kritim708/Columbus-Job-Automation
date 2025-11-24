# Columbus Job Automation Project

This project automates the setup and execution of Columbus quantum chemistry calculations, including MCSCF, CISD, and AQCC jobs. It streamlines the process by automatically handling file management, input generation, and job execution.

## Project Structure

- `main.sh` - Main script that orchestrates the entire workflow
- `Scripts/`
  - `input.sh` - Collects basic input parameters for Columbus calculations
  - `input_values.txt` - Generated file containing all input parameters
  - `part_i-make_geom.sh` - Converts XYZ files to Columbus geometry format
  - `part_iii-colinp_automate.exp` - Handles MCSCF calculation automation
  - `part_iv-colinp_automate.exp` - Handles CISD calculation automation
  - `part_v-colinp_automate.exp` - Handles AQCC calculation automation

## Prerequisites

- Columbus 7.0 or higher must be installed
- Expect scripting tool must be available
- Linux/Unix environment with bash shell

## Usage Guide

1. **Prepare Your Files**
   - Have the path of your XYZ geometry file ready to input
   - Ensure the bash file are made executable using following command:
   ```chmod +x main.sh
   chmod +x Scripts/input.sh
   chmod +x Scripts/part_i-make_geom.sh```

2. **Run the Main Script**
   ```bash
   bash main.sh
   ```

3. **Input Basic Parameters**
   The script will ask for several parameters:
   - Number of unique elements in your molecule
   - Calculation set (cc-pvdz=1 or cc-pvtz=6)
   - Group symmetry (e.g., cs, c2v)
   - Spatial symmetry
   - Multiplicity (Singlet=1 or Triplet=3)
   - Various orbital specifications from DRT table:
     - Number of electrons
     - SCF doubly occupied orbitals
     - SCF open-shell orbitals
     - MCSCF doubly occupied orbitals
     - MCSCF active space
     - MRCI frozen core
     - MRCI frozen virtual
     - MRCI doubly occupied orbitals
     - MRCI active orbitals
     - MRCI auxiliary orbitals
     - MRCI internal orbitals

4. **Select Calculation Types**
   You'll be prompted to choose which calculations to run:
   - MCSCF (y/n)
   - CISD (y/n)
   - AQCC (y/n)

5. **Customize Parameters (Optional)**
   For each selected calculation type, you can customize:
   - Number of iterations
   - Number of optimization cycles
   (Default values will be used if not specified)


## Configuring Memory Allocation

The default memory allocation for calculations is 4000 MB. To increase memory for larger systems:

1. **Open `main.sh` in a text editor**

2. **Locate and modify the following lines**:

   - **For MCSCF** (around line 170):
```bash
     $COLUMBUS/runc -m 4000 > runls &
```

   - **For CISD** (around line 205):
```bash
     $COLUMBUS/runc -m 4000 > runls &
```

   - **For AQCC** (around line 239):
```bash
     $COLUMBUS/runc -m 4000 > runls &
```

3. **Change `4000` to your desired memory in MB**:
```bash
   $COLUMBUS/runc -m 8000 > runls &    # For 8 GB
   $COLUMBUS/runc -m 16000 > runls &   # For 16 GB
```

**Note**: Ensure your system has sufficient RAM available before increasing memory allocation.



## Output Structure

The script creates a `Columbus` directory with subdirectories for each calculation type:
- `Columbus/MCSCF/` - MCSCF calculation files and results
- `Columbus/CI/` - CISD calculation files and results
- `Columbus/AQCC/` - AQCC calculation files and results

## Important Notes

- You can reuse previously entered parameters by keeping the generated `input_values.txt` file
- All calculations will be performed sequentially (MCSCF → CISD → AQCC)
- Each stage's output is preserved in its respective directory
- A log file (`log.out`) is created in the root directory to track the entire process

## Error Handling

- The script checks for the existence of required files and directories
- Clear error messages are provided if prerequisites are not met
- Each stage's completion is verified before proceeding to the next

