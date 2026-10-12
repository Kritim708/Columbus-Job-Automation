import os
import re

# Job Convergence variables
GEOMS_DIR = "GEOMS"
LISTINGS_DIR = "LISTINGS"
TAIL_BYTES = 5 * (1024 ** 2)  # only read the last 5 MB of big listing files
FLOAT = r"-?\d+\.\d+"


# Intruder States variables
CIPCLS_FILE = "cipcls.drt1.all"
INTRUDER_C2_THRESHOLD = 0.01
# step-vector digit -> (number of electrons, description)
STEP_INFO = {
    "0": (0, "vacant"),
    "1": (1, "singly occupied (spin 1)"),
    "2": (1, "singly occupied (spin 2)"),
    "3": (2, "doubly occupied"),
}

CSF_HEADER = re.compile(r"^\s*indcsf\s+c\s+c\*\*2")


# ---------------------------------------------------------------- helpers
def read_tail(path, nbytes=TAIL_BYTES):
    """Read the last nbytes of a text file (whole file if smaller)."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - nbytes))
        return f.read().decode("utf-8", errors="replace")


def check_geom_min(job_dir):
    """Return None if geom.min exists in GEOMS, else a reason string."""
    geoms = os.path.join(job_dir, GEOMS_DIR)
    if not os.path.isdir(geoms):
        return f"{GEOMS_DIR} folder not found"
    if not os.path.isfile(os.path.join(geoms, "geom.min")):
        return f"geom.min not found in {GEOMS_DIR}"
    return None


def check_geometry_converged(job_dir):
    """Return None if gdiisls.all has the geometry convergence line."""
    path = os.path.join(job_dir, LISTINGS_DIR, "gdiisls.all")
    if not os.path.isfile(path):
        return "LISTINGS/gdiisls.all not found"
    if "*** Geometry optimization converged! ***" not in read_tail(path):
        return "geometry optimization convergence line not found in gdiisls.all"
    return None


def result(reasons, values):
    return {
        "converged": not reasons,
        "values": values,
        "reasons": reasons,
    }