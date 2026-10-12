#!/usr/bin/env python3
"""
Convergence & Intruder checks for MCSCF, CISD and AQCC jobs.

Each check takes a job directory and returns a dict:
    {"converged": bool, "values": {...}, "reasons": [...]}
"values" holds the extracted energies (floats); "reasons" lists whatever
failed (empty when converged).

Usage:
    python3 main.py {mcscf|cisd|aqcc} /path/to/job_dir [more_dirs ...]
    python3 main.py intruder -n <n_active_orbitals> /path/to/job_dir [...]
        [-t <c**2 threshold, default 0.1>]
"""

import argparse
from helper import *
from check_intruder import print_intruder_report, check_intruder_states
from check_convergence import check_MCSCF_convergence, check_CISD_convergence, check_AQCC_convergence

# -------------------------------------------------------------------- CLI
CHECKS = {
    "mcscf": ("MCSCF", check_MCSCF_convergence),
    "cisd": ("CISD", check_CISD_convergence),
    "aqcc": ("AQCC", check_AQCC_convergence),
}


def report(method, job_dir):
    name, fn = CHECKS[method]
    res = fn(job_dir)
    status = "converged" if res["converged"] else "NOT converged"
    vals = ", ".join(f"{k}={v}" for k, v in res["values"].items())
    print(f"{job_dir}: {name} {status}" + (f"  [{vals}]" if res["converged"] and vals else ""))
    for reason in res["reasons"]:
        print(f"    - {reason}")


def main():
    ap = argparse.ArgumentParser(
        description="Convergence and intruder-state checks for Columbus jobs.")
    ap.add_argument("method", type=str.lower,
                    choices=["mcscf", "cisd", "aqcc", "intruder"])
    ap.add_argument("dirs", nargs="+", help="job directories")
    ap.add_argument("-n", "--n-active", type=int,
                    help="number of active orbitals (required for 'intruder')")
    ap.add_argument("-t", "--threshold", type=float, default=INTRUDER_C2_THRESHOLD,
                    help="C**2 threshold for intruder detection (default 0.01)")
    args = ap.parse_args()

    if args.method == "intruder":
        if not args.n_active:
            ap.error("'intruder' requires -n/--n-active (number of active orbitals)")
        for d in args.dirs:
            res = check_intruder_states(d, args.n_active, args.threshold)
            print_intruder_report(d, res, args.n_active, args.threshold)
            print()
    else:
        for d in args.dirs:
            report(args.method, d)


if __name__ == "__main__":
    main()