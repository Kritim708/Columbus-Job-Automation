# Columbus Job Automation Project

This project automates the setup and execution of Columbus quantum chemistry calculations, including MCSCF, CISD, and AQCC jobs. The workflow has been streamlined with modular scripts and a flexible output structure, making it easier to manage and track complex calculations.

---

## Project Structure

- `main.sh`
  - Entry point for initializing and adding diradicals.
- `Scripts/`
  - `run.sh`: Stages method scripts into the calculation prep directories.
  - `AQCC/`, `CISD/`, `MCSCF/`: Each contains its method launcher and corresponding Expect scripts.
  - `Utilities/`: Geometry conversion, DRT parsing, log conversion, and manual input helpers.
  - `diradicals/<NAME>/`: Source DRT/geometry plus that diradical's `input_values.txt` and Columbus `geom`.
  - `config.txt` and shared templates remain at the `Scripts/` root.

**Note:** The parallel execution scripts (`*par.exp`) are under development and may not be fully functional.



- Columbus 7.0 or higher installed
- Linux/Unix environment (bash shell)
- Expect scripting tool installed
- Python 3 (for DRT.xlsx parsing via `parse_drt.py`)
- Python packages:
  - `pandas` – for reading and parsing Excel files

---

Below is exactly what main.sh asks for (in order) and how to respond or use the options it provides.

1) Start
- Make sure scripts are executable:
  ```bash
  chmod +x main.sh
  chmod +x Scripts/*.sh Scripts/AQCC/*.sh Scripts/CISD/*.sh Scripts/MCSCF/*.sh Scripts/Utilities/*.sh
  chmod +x Scripts/AQCC/*.exp Scripts/CISD/*.exp Scripts/MCSCF/*.exp
  ```
- Run:
  ```bash
  bash main.sh initialize
  ```

You can add another diradical later with `bash main.sh add_diradical thiazole_45` (omit the name to be prompted for it).
Remove one with `bash main.sh remove_diradical thiazole_45`. The command lists existing per-diradical paths and asks for confirmation before deleting them; missing paths are skipped.
Set or change the Columbus installation with `bash main.sh -columbus_path "/path/to/Columbus"`. Initialization reuses the configured path and prompts only when `Scripts/config.txt` has no `COLUMBUS=` value.

2) Diradical inputs
- Enter all diradical names, then provide a geometry file for each one (`.xyz`, `.log`, or Columbus `geom`).
- Choose whether to use one DRT table for all diradicals or provide a separate `.xlsx` for each.
- Inputs and generated files are stored under `Scripts/diradicals/<NAME>/`; `Scripts/run.sh` stages the matching `geom` and values into each prep directory.


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
  - Each initialized diradical keeps its DRT-derived values under `Scripts/diradicals/<NAME>/input_values.txt` for later staging.
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
