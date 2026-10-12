import os
import re
from helper import *



# ------------------------------------------------------------------ MCSCF
def check_MCSCF_convergence(job_dir):
    reasons, values = [], {}

    r = check_geom_min(job_dir)
    if r:
        reasons.append(r)

    path = os.path.join(job_dir, LISTINGS_DIR, "mcscfsm.all")
    if not os.path.isfile(path):
        reasons.append("LISTINGS/mcscfsm.all not found")
        return result(reasons, values)

    lines = read_tail(path).splitlines()

    # Use the LAST "final mcscf convergence values:" block in the file.
    idx = None
    for i, line in enumerate(lines):
        if "final mcscf convergence values:" in line:
            idx = i
    if idx is None:
        reasons.append("'final mcscf convergence values:' not found")
        return result(reasons, values)

    # The data line is the next non-blank line.
    data = next((l for l in lines[idx + 1:] if l.strip()), "")
    if "*converged*" not in data:
        reasons.append("*converged* not found on the final MCSCF line")
    m = re.match(rf"\s*\d+\s+({FLOAT})", data)
    if m:
        values["MCSCF"] = float(m.group(1))
    else:
        reasons.append("could not parse MCSCF energy")

    return result(reasons, values)


# ------------------------------------------------------- CISD / AQCC core
def _check_ci(job_dir, method):
    """Shared logic for CISD (mr-sdci) and AQCC (mraqcc)."""
    reasons, values = [], {}

    r = check_geom_min(job_dir)
    if r:
        reasons.append(r)
    r = check_geometry_converged(job_dir)
    if r:
        reasons.append(r)

    path = os.path.join(job_dir, LISTINGS_DIR, "ciudgsm.all")
    if not os.path.isfile(path):
        reasons.append("LISTINGS/ciudgsm.all not found")
        return result(reasons, values)

    text = read_tail(path)
    tag = "mr-sdci" if method == "CISD" else "mraqcc"

    conv = None
    for conv in re.finditer(
            rf"{tag}\s+convergence criteria satisfied after\s+(\d+)\s+iterations", text):
        pass  # keep the last match
    if conv is None:
        reasons.append(f"'{tag} convergence criteria satisfied' line not found in ciudgsm.all")
        return result(reasons, values)

    values["iterations"] = int(conv.group(1))
    after = text[conv.end():]

    if method == "CISD":
        m = re.search(rf"^\s*eci\s+=\s+({FLOAT})", after, re.M)
        if m:
            values["MRCISD"] = float(m.group(1))
        else:
            reasons.append("could not find 'eci' value")
        m = re.search(rf"^\s*eci\+pople\s+=\s+({FLOAT})", after, re.M)
        if m:
            values["MRCISD+Q"] = float(m.group(1))
        else:
            reasons.append("could not find 'eci+pople' value")
    else:
        m = re.search(rf"mraqcc\s*#\s*\d+\s+\d+\s+({FLOAT})", after)
        if m:
            values["AQCC"] = float(m.group(1))
        else:
            reasons.append("could not find final mraqcc energy")

    return result(reasons, values)


def check_CISD_convergence(job_dir):
    return _check_ci(job_dir, "CISD")


def check_AQCC_convergence(job_dir):
    return _check_ci(job_dir, "AQCC")





