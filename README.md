# Columbus Job Automation Project

This project automates the setup and execution of Columbus quantum chemistry calculations, including MCSCF, CISD, and AQCC jobs. The workflow has been streamlined with modular scripts and a flexible output structure, making it easier to manage and track complex calculations.

---

## Project Structure

- `main.sh`
  - Entry point: collects high-level information from the user (e.g., calculation set and multiplicity).
- `Scripts/`
  - `run.sh`: Drives the workflow, determines calculation settings (Singlet/Triplet and DZ/TZ), and conditionally launches MCSCF, CISD, and AQCC stages.
  - `make_geom.sh`: Converts your XYZ geometry file to the Columbus input format.
  - `mcscf.exp`, `cisd-ser.exp`, `cisd-par.exp`, `aqcc-ser.exp`, `aqcc-par.exp`: Expect scripts for automating each calculation stage, with “ser” for serial and “par” for parallel execution. *Parallel mode is under development.*
  - Other supplementary files: config.txt, input_values.txt etc.

**Note:** The parallel execution scripts (`*par.exp`) are under development and may not be fully functional.

---

## Prerequisites

- Columbus 7.0 or higher installed
- Linux/Unix environment (bash shell)
- Expect scripting tool installed
- Python 3 (for DRT.xlsx parsing via `parse_drt.py`)
- Python packages:
  - `pandas` – for reading and parsing Excel files
  - `openpyxl` – backend for reading .xlsx files (installed with pandas)

---

## Workflow (what you actually do)

Short answer: run main.sh and follow the prompts. main.sh calls Scripts/input.sh and then hands off to Scripts/run.sh, which performs all remaining steps (geometry conversion, creating output folders, running expect scripts and Columbus runc, and logging).

Below is exactly what main.sh asks for (in order) and how to respond or use the options it provides.

1) Start
- Make sure scripts are executable:
  ```bash
  chmod +x main.sh
  chmod +x Scripts/*.sh
  chmod +x Scripts/*.exp
  ```
- Run:
  ```bash
  bash main.sh
  ```

2) Columbus installation directory
- Prompt: Enter Columbus directory (default is /usr/local/chem.sw/Columbus).
- main.sh verifies that the provided directory contains both `runc` and `colinp`. Exported to the run environment as COLUMBUS.
- Tip: If verification fails, check the path and try again.

3) Geometry (.xyz) file
- main.sh switches into the Scripts directory and looks for .xyz files there.
- If .xyz files are present you can select one or choose "Import a new .xyz file".
- If none are present you will be asked for the full path to your .xyz file; it will be copied into Scripts.
- After selection, the script runs `Scripts/make_geom.sh <selected_xyz> <COLUMBUS>` which calls Columbus's xyz2col.x to create the geometry file used by Columbus.

4) Input values configuration
- main.sh presents a menu with three options for configuring input values:
  - **Use existing input_values.txt** (if available) — skip re-entering basic parameters.
  - **Import DRT.xlsx** — runs `Scripts/parse_drt.py` to parse DRT (Doubly-Rooted Ternary) values from an Excel file. You can specify a custom directory or use the default (Scripts/DRT.xlsx).
  - **Manually enter input values (input.sh)** — runs `Scripts/input.sh` and prompts for the following fields:
    - Number of unique atoms (num_unique_atoms)
    - Group symmetry (e.g., cs, c2v)
    - Spatial symmetry
    - DRT-table related values:
      - Number of electrons (num_electrons)
      - SCF doubly occupied orbitals (scf_docc)
      - SCF open-shell orbitals (scf_opsh)
      - MCSCF doubly occupied orbitals (mcscf_docc)
      - MCSCF active space (mcscf_cas)
      - MRCI frozen core (mrci_fc)
      - MRCI frozen virtual (mrci_fv)
      - MRCI doubly occupied orbitals (mrci_docc)
      - MRCI auxiliary orbitals (mrci_aux)
      - MRCI internal orbitals (mrci_int)
- At the end input_values.txt is written into Scripts and later copied into each run's output directory.

5) Calculation set and multiplicity (high-level choices)
- Prompt: Select calculation set:
  - 1 → cc-pvdz (labelled DZ)
  - 6 → cc-pvtz (labelled TZ)
- Prompt: Select multiplicity:
  - 1 → Singlet
  - 3 → Triplet
  - (You may select only one option in the default flow; configuration allows preparing for one or both multiplicities)

6) Run mode (serial vs parallel)
- Prompt: Do you want to run in parallel mode? (y/n)
  - If yes, you will be prompted for parallel configuration values which are appended to `input_values.txt`:
    - Number of cores (`ncores`, default 4)
    - Memory per core in MB (`mem_per_core`, default 750)
    - Effective bandwidth (`bandwidth`, default 50)
    - Processors per node (`processor_per_node`, default 4)
    - Core memory in MB (`core_memory`, default 20000)
  - If no, the script defaults to serial mode execution.
- Note: Parallel mode uses the `*-par.exp` expect scripts; these are marked experimental — if you do not need parallel execution, prefer serial mode.

7) Slurm submission choice
- Prompt: Do you want to submit jobs via Slurm? (y/n)
  - If yes, the script displays important validation reminders:
    - Verify the Slurm file is on the cluster/workstation you're using.
    - Check that your email address is correct.
    - Ensure core and memory requests are appropriate.
    - Verify other Slurm parameters (timing, account, etc.) are set correctly.
  - You must then provide the full path to your Slurm submission file; it will be copied into the Scripts directory as `columbus.slurm`.
  - The script will use `sbatch` to submit jobs when Slurm is selected.
  - If no, the script invokes `$COLUMBUS/runc` locally.

8) Per-multiplicity job options (for each selected multiplicity)
- For each multiplicity (Singlet and/or Triplet) you will be asked:
  - Do you want to run MCSCF? (y/n)
    - If yes, you will be prompted for:
      - MCSCF iterations (mcscf_iter) (default -1 = automatic)
      - MCSCF optimization cycles (mcscf_opt_iter) (default -1)
      - Memory for MCSCF (mcscf_mem) in MB (default 4000)
  - Do you want to run CISD? (y/n)
    - If yes, you will be prompted for:
      - CISD iterations (cisd_iter) (default -1)
      - CISD optimization cycles (cisd_opt_iter) (default -1)
      - Memory for CISD (cisd_mem) in MB (default 4000)
  - Do you want to run AQCC? (y/n)
    - If yes, you will be prompted for:
      - AQCC iterations (aqcc_iter) (default -1)
      - AQCC optimization cycles (aqcc_opt_iter) (default -1)
      - Memory for AQCC (aqcc_mem) in MB (default 4000)
- The script bundles these into a per-multiplicity `input_values.txt` under:
  - `Columbus/<DZ|TZ>/<Singlet|Triplet>/input_values.txt`

9) What main.sh does next
- main.sh writes a `config.txt` that contains:
  - calculation_set, run_parallel, use_slurm, slurm_path
  - run_mcscf_*, run_cisd_*, run_aqcc_* flags for each multiplicity
  - memory settings for each multiplicity/stage
  - COLUMBUS path
- main.sh then launches `Scripts/run.sh <Multiplicity>` in the background for each selected multiplicity.

10) What `run.sh` does (high-level)
- Loads `config.txt` and selects run parameters appropriate for the multiplicity passed to it.
- Converts the calculation_set number to text label (DZ or TZ).
- Determines run mode: `ser` or `par` depending on run_parallel.
- Redirects all output to `Columbus/<DZ|TZ>/<Multiplicity>/log.out`.
- MCSCF stage (if selected):
  - Creates `MCSCF/` folder, copies input files and `mcscf.exp`, runs expect on `mcscf.exp`, then runs `$COLUMBUS/runc -m <mcscf_mem>` (or submits Slurm job).
  - On success copies `MOCOEFS/mocoef_mc.sp` to `mocoef` for downstream use.
- CISD stage (if selected):
  - Prepares `CI/`, copies files and the appropriate `cisd-<ser|par>.exp`.
  - Runs expect script; if `runc.error` contains "not enough memory" and "pscript failed" it will retry the expect script (so you may need to increase memory and re-run if the loop repeats).
  - Runs `$COLUMBUS/runc -m <cisd_mem>` (or submits Slurm job).
- AQCC stage (if selected):
  - Similar to CISD: copies `aqcc-<ser|par>.exp`, retries expect on memory-detected failures, and runs `$COLUMBUS/runc -m <aqcc_mem>` (or via Slurm).
- After all selected stages the script reports completion to the log.

---

## What to watch for and quick troubleshooting

- COLUMBUS path: main.sh will check that `$COLUMBUS/runc` and `$COLUMBUS/colinp` exist. Fix the path if verification fails.
- Expect must be installed and callable (used by the `.exp` scripts).
- If you see repeated "not enough memory" and "pscript failed" in `runc.error`, increase the memory values when re-running main.sh (or edit the produced `config.txt`/`input_values.txt` and re-run the relevant stage manually).
- Logs:
  - Main consolidated log: `log.out` (created in repo root by main.sh)
  - Per-run log: `Columbus/<DZ|TZ>/<Singlet|Triplet>/log.out`
  - Per-stage runc errors may be in `runc.error` inside the stage directory.
- Reuse inputs:
  - If `Scripts/input_values.txt` already exists you can choose to reuse it and avoid retyping the DRT-table values.
- Parallel mode:
  - Experimental — verify resource availability and test on small systems before large production runs.
- Slurm:
  - If you choose Slurm, ensure your slurm file has correct email, core and memory requests, and is accessible from the machine where you run main.sh.

---

## Output Structure

Results are organized as follows:

- `Columbus/DZ/` – All calculations using DZ basis
- `Columbus/TZ/` – All calculations using TZ basis
  - Each contains subfolders by multiplicity:
    - `Singlet/`
    - `Triplet/`
      - Each contains:
        - `MCSCF/`
        - `CI/` (from CISD)
        - `AQCC/`

Example path for your results:
```
Columbus/DZ/Singlet/MCSCF/
Columbus/DZ/Singlet/CI/
Columbus/DZ/Singlet/AQCC/
```
A comprehensive log (`log.out`) is maintained per run.

---

## Error Handling

- All critical steps validate input files and detect environment issues (e.g., missing geometry, configuration errors, low memory).
- Clear error messages are provided where available; repeated memory failures may require updating memory parameters and re-running.
- Each stage's completion is verified before proceeding to the next.

---

## Notes for Users

- You can reuse parameters by keeping the generated configuration and input files.
- All calculations are performed in a staged manner.
- Parallel execution is experimental — prefer serial scripts unless you have tested your cluster/job system setup.
- For advanced users: memory settings and Slurm support can be customized during your input process.

---

**See each `.sh` and `.exp` file for details as the internal workflow may change. For development or troubleshooting, inspect the log files and output folders in Columbus.**
