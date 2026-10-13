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
  - `config.txt` and shared templates remain beside the source scripts.
- The current working directory is the calculation workspace. `diradicals/<NAME>/` stores source DRT/geometry and parsed values; `Columbus/` stores the DZ/TZ calculations.

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
  chmod +x /path/to/Columbus-Job-Automation/Scripts/run.sh
  chmod +x /path/to/Columbus-Job-Automation/Scripts/AQCC/*.sh /path/to/Columbus-Job-Automation/Scripts/CISD/*.sh /path/to/Columbus-Job-Automation/Scripts/MCSCF/*.sh /path/to/Columbus-Job-Automation/Scripts/Utilities/*.sh
  ```
- Run:
  ```bash
  cd /path/to/calculation-workspace
  bash /path/to/Columbus-Job-Automation/main.sh initialize
  ```

You can add another diradical later with `bash /path/to/Columbus-Job-Automation/main.sh add_diradical thiazole_45` (omit the name to be prompted for it).
Remove one with `bash /path/to/Columbus-Job-Automation/main.sh remove_diradical thiazole_45`. The command lists existing per-diradical paths and asks for confirmation before deleting them; missing paths are skipped.
Set or change the Columbus installation with `bash /path/to/Columbus-Job-Automation/main.sh -columbus_path "/path/to/Columbus"`. Initialization reuses the configured path and prompts only when the code repository's `Scripts/config.txt` has no `COLUMBUS=` value.

2) Diradical inputs
- Enter all diradical names, then provide a geometry file for each one (`.xyz`, `.log`, or Columbus `geom`).
- Choose whether to use one DRT table for all diradicals or provide a separate `.xlsx` for each.
- Inputs and generated files are stored under `diradicals/<NAME>/` in the current working directory; run the repository's `Scripts/run.sh` from that same directory to stage them into `Columbus/`.


3) Stage calculation inputs
- From the same calculation workspace, run the repository's staging script:
  `bash /path/to/Columbus-Job-Automation/Scripts/run.sh [options]`
- It reads `diradicals/` and creates or refreshes prep directories under the workspace's `Columbus/` tree.
- Each prep directory receives its `geom`, generated `input_values.txt`, method launcher and Expect files, plus `config.txt` containing the source `SCRIPTS_DIR` for convergence checks.

---

## What to watch for and quick troubleshooting

- COLUMBUS path: configure with `main.sh -columbus_path`; it checks for `runc`, `colinp`, and `xyz2col.x`.
- Expect must be installed and callable (used by the `.exp` scripts).
- If you see repeated "not enough memory" and "pscript failed" in `runc.error`, increase the memory values when re-running main.sh (or edit the produced `config.txt`/`input_values.txt` and re-run the relevant stage manually).
- Logs:
  - Main consolidated log: `log.out` (created in the calculation workspace by the workflow)
  - Per-run log: `Columbus/<DZ|TZ>/<Singlet|Triplet>/log.out`
  - Per-stage runc errors may be in `runc.error` inside the stage directory.
- Reuse inputs:
  - Each initialized diradical keeps its DRT-derived values under `diradicals/<NAME>/input_values.txt` in the calculation workspace.
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
