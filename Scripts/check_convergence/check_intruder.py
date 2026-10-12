import os
import re
from helper import *


# -------------------------------------------------------- intruder states
# Protocol: in LISTINGS/cipcls.drt1.all, go to the bottom and scroll up to the
# top of the step-vector table.  A line with C**2 > 0.1 and a "z" WITHOUT an
# asterisk is a CSF outside the reference space with a large weight, i.e. an
# intruder state. The step vector says which excitation it is. Check helper 
# functions for details.


def _parse_block(lines, i):
    """Tokens after '=' on line i, plus continuation lines (no '=' in them)."""
    tokens = lines[i].split("=", 1)[1].split()
    j = i + 1
    while j < len(lines) and lines[j].strip() and "=" not in lines[j]:
        tokens += lines[j].split()
        j += 1
    return tokens


def _last_line(lines, pattern, end):
    """Index of the last line before `end` matching pattern, or None."""
    rx = re.compile(pattern)
    for i in range(end - 1, -1, -1):
        if rx.match(lines[i]):
            return i
    return None


def _parse_csf_table(lines, head):
    """Rows of the step-vector table that starts after line `head`."""
    rows = []
    for line in lines[head + 1:]:
        s = line.strip()
        if not s:
            if rows: break
            continue
        if set(s) <= set("- "):  # the dashed separator line
            continue
        t = s.split()
        if len(t) >= 5 and t[0].isdigit() and re.fullmatch(r"[0-3]+", t[-1]):
            try:
                c, c2 = float(t[1]), float(t[2])
            except ValueError:
                break
            rows.append({"indcsf": int(t[0]), "c": c, "c2": c2,
                         "v": t[3], "other": t[4:-1], "step": t[-1]})
        else:
            break
    return rows


def _region(k, first_active):
    return "active" if k >= first_active else "non-active"


def _compare(ref_step, step, key, first_active):
    """Per-orbital differences between two step vectors."""
    changes = []
    for k, (a, b) in enumerate(zip(ref_step, step)):
        if a == b:
            continue
        changes.append({
            "level": key[k]["level"], "label": key[k]["label"], "rmo": key[k]["rmo"],
            "region": _region(k, first_active),
            "ref": a, "new": b,
            "d_elec": STEP_INFO[b][0] - STEP_INFO[a][0],
        })
    return changes


def _summarize(changes):
    donors = [c for c in changes if c["d_elec"] < 0]
    acceptors = [c for c in changes if c["d_elec"] > 0]
    n = sum(-c["d_elec"] for c in donors)
    if n == 0:
        return 0, ("same orbital occupations as the reference; only the spin "
                   "coupling differs")

    def fmt(c):
        return f"{c['label']} #{c['rmo']} (level {c['level']}, {c['region']})"

    rank = {1: "single", 2: "double", 3: "triple"}.get(n, f"{n}-electron")
    text = (f"{rank} excitation ({n} e- moved): out of "
            + ", ".join(fmt(c) for c in donors)
            + "; into " + ", ".join(fmt(c) for c in acceptors))
    src = {c["region"] for c in donors}
    dst = {c["region"] for c in acceptors}
    text += f"  [{'/'.join(sorted(src))} -> {'/'.join(sorted(dst))}]"
    return n, text


def check_intruder_states(job_dir, n_active, threshold=INTRUDER_C2_THRESHOLD):
    """
    Look for intruder states in LISTINGS/cipcls.drt1.all.

    n_active: number of active orbitals (the last n_active entries of the
    label key / step vector).

    Returns {"checked": bool, "intruders_present": bool|None,
             "info": {...}, "reasons": [...], "warnings": [...]}.
    "checked" is False if the check could not be done (missing file, etc.).
    """
    info = {"file": os.path.join(job_dir, LISTINGS_DIR, CIPCLS_FILE),
            "key": [], "reference": None, "intruders": [], "slabel": None,
            "top_nonref": None}
    warnings = []

    def fail(msg):
        return {"checked": False, "intruders_present": None, "info": info,
                "reasons": [msg], "warnings": warnings}

    if not os.path.isfile(info["file"]):
        return fail(f"LISTINGS/{CIPCLS_FILE} not found - cannot check for intruder states")

    lines = read_tail(info["file"]).splitlines()

    head = None
    for i, line in enumerate(lines):
        if CSF_HEADER.match(line):
            head = i  # keep the LAST table in the file
    if head is None:
        return fail("step-vector table ('indcsf c c**2 ...') not found in the "
                    "last 2 MB of the file")

    rows = _parse_csf_table(lines, head)
    if not rows:
        return fail("step-vector table found but no CSF rows could be parsed")

    # ---- label key above the table
    i_label = _last_line(lines, r"^\s*label\s*=", head)
    i_rmo = _last_line(lines, r"^\s*rmo\(\*\)\s*=", head)
    i_lev = _last_line(lines, r"^\s*internal level\s*=", head)
    i_sym = _last_line(lines, r"^\s*i:slabel\(i\)\s*=", head)
    if i_label is None or i_rmo is None:
        return fail("label key ('label =' / 'rmo(*) =') not found above the table")

    labels = _parse_block(lines, i_label)
    rmo = _parse_block(lines, i_rmo)
    levels = _parse_block(lines, i_lev) if i_lev is not None else None
    if i_sym is not None:
        info["slabel"] = lines[i_sym].split("=", 1)[1].strip()

    L = len(rows[0]["step"])
    if len(labels) != L or len(rmo) != L:
        return fail(f"label key has {len(labels)} labels / {len(rmo)} rmo entries "
                    f"but step vectors have {L} digits")
    if levels is None or len(levels) != L:
        levels = [str(k + 1) for k in range(L)]
    if not 1 <= n_active <= L:
        return fail(f"n_active={n_active} is not valid for {L} internal orbitals")

    first_active = L - n_active
    info["key"] = [{"level": levels[k], "label": labels[k], "rmo": rmo[k],
                    "region": _region(k, first_active)} for k in range(L)]

    # ---- reference CSF = highest-weight row inside the reference space ('*')
    ref = next((r for r in rows if r["v"].endswith("*")), None)
    if ref is None:
        return fail("no reference-space CSF (flag with '*') found in the table")
    info["reference"] = ref
    if ref is not rows[0]:
        warnings.append("the dominant CSF in the table is not in the reference "
                        "space; the first reference-space CSF is used for comparison")

    # ---- sanity check of n_active: orbitals outside the active space are
    # doubly occupied in EVERY reference-space CSF (flagged '*'), so a '*' CSF
    # that is not '3' at a "non-active" level means n_active is too small.
    # worst = None
    # for r in rows:
    #     if r["v"].endswith("*") and len(r["step"]) == L:
    #         k = next((k for k, d in enumerate(r["step"]) if d != "3"), None)
    #         if k is not None and k < first_active and (worst is None or k < worst[0]):
    #             worst = (k, r)
    # if worst:
    #     k, r = worst
    #     warnings.append(
    #         f"n_active={n_active} looks too small: reference-space CSF {r['indcsf']} "
    #         f"(marked *) is not doubly occupied at level {levels[k]} "
    #         f"({labels[k]} #{rmo[k]}), which you treat as non-active. The active "
    #         f"space is at least {L - k} orbitals.")

    # ---- intruders: 'z' CSFs (all orbitals internal) WITHOUT '*' and C**2 above
    # threshold.  y/x/w rows (1-2 external orbitals) carry extra leading digits
    # in step(*) for the external orbitals, so they are not intruders and not
    # comparable with the internal step vector; they are skipped here.
    info["top_nonref"] = next((r for r in rows if r["v"] == "z"), None)
    for r in rows:
        if r["v"] != "z" or r["c2"] <= threshold:
            continue
        if len(r["step"]) != L:
            continue
        changes = _compare(ref["step"], r["step"], info["key"], first_active)
        n_moved, summary = _summarize(changes)
        info["intruders"].append({"row": r, "changes": changes,
                                  "n_moved": n_moved, "summary": summary})
        break

    return {"checked": True, "intruders_present": bool(info["intruders"]),
            "info": info, "reasons": [], "warnings": warnings}


def _split_step(step, n_active):
    return step[:-n_active] + "|" + step[-n_active:]


def print_intruder_report(job_dir, res, n_active, threshold):
    print(f"{job_dir}: intruder-state check (C**2 > {threshold}, no '*')")
    for w in res["warnings"]:
        print(f"    ! {w}")
    if not res["checked"]:
        for reason in res["reasons"]:
            print(f"    - could not check: {reason}")
        return
    if not res["intruders_present"]:
        print("    No intruder states found (good).")
        top = res["info"]["top_nonref"]
        if top:
            print(f"    (largest CSF outside the reference space: indcsf {top['indcsf']}, "
                  f"c**2 = {top['c2']:.5f}, below the {threshold} threshold)")
        return

    info = res["info"]
    ref = info["reference"]
    # print(f"    INTRUDER STATE(S) FOUND: {len(info['intruders'])}")
    print(f"Largest Intruder State:")
    print(f"    File: {info['file']}")
    if info["slabel"]:
        print(f"    Symmetry key: {info['slabel']}")

    print(f"\n    Label key (internal orbitals; the last {n_active} are the active space):")
    print("      level  label  rmo  region      reference occupation")
    for k, e in enumerate(info["key"]):
        d = ref["step"][k]
        print(f"      {e['level']:>5}  {e['label']:<5}  {e['rmo']:>3}  {e['region']:<10}  "
              f"{d} = {STEP_INFO[d][1]}")

    print(f"\n    Reference CSF: indcsf {ref['indcsf']}  c={ref['c']:.5f}  c**2={ref['c2']:.5f}")
    print(f"      step vector (non-active | active): {_split_step(ref['step'], n_active)}")
    act = info["key"][-n_active:]
    print("      active space: " + " ".join(
        f"{e['label']}#{e['rmo']}={ref['step'][-n_active + i]}" for i, e in enumerate(act)))

    for it in info["intruders"]:
        r = it["row"]
        print(f"\n    Intruder: indcsf {r['indcsf']}  c={r['c']:.5f}  c**2={r['c2']:.5f}  v={r['v']}")
        print(f"      step vector (non-active | active): {_split_step(r['step'], n_active)}")
        print("      changes relative to the reference:")
        for c in it["changes"]:
            print(f"        level {c['level']:>3}  {c['label']} #{c['rmo']}  ({c['region']}): "
                  f"{c['ref']} -> {c['new']}  "
                  f"({STEP_INFO[c['ref']][1]} -> {STEP_INFO[c['new']][1]}, "
                  f"{c['d_elec']:+d} e-)")
        print(f"      interpretation: {it['summary']}")

    print("\n    Next step: look up these label/rmo entries (symmetry + orbital number "
          "within that symmetry)\n    on your orbital sheet to see which orbitals the "
          "electrons leave and enter.")