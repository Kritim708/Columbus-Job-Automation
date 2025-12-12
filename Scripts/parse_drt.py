#   USAGE:
# ------------------------- 
# python parse_drt.py                               # uses default Scripts/DRT.xlsx
# python parse_drt.py "path/to/your/DRT.xlsx"       # uses user-specified path

import os
import re
import shutil
import sys
import pandas as pd

# -------------------------
# Helper extraction methods
# -------------------------

def extract_point_group(text):
    parts = str(text).strip().split()
    pg = parts[-1].lower()
    if pg not in ["c2v", "cs"]:
        raise ValueError(f"Invalid point group extracted: {pg}")
    return pg

def extract_symmetry(text):
    text = str(text)
    m = re.search(r"\((\d+)\)", text)
    if not m:
        raise ValueError(f"Could not extract symmetry from '{text}'")
    return int(m.group(1))

def extract_spin_from_multiplicity(mult):
    try:
        m = int(mult)
    except:
        raise ValueError(f"Invalid multiplicity: {mult}")

    if m == 1:
        return "Singlet"
    elif m == 3:
        return "Triplet"
    else:
        raise ValueError(f"Invalid multiplicity '{m}': must be 1 or 3")

def parse_row_values(row, col_indices):
    return " ".join(str(row[i]) for i in col_indices)


# --------------------------------------------
# Main program
# --------------------------------------------

def main():
    # ------------------------------------------
    # Handle command-line argument
    # ------------------------------------------
    default_path = "Scripts/DRT.xlsx"

    # User provided: python parse_drt.py "path/file.xlsx"
    if len(sys.argv) > 1:
        excel_path = sys.argv[1]
    else:
        excel_path = default_path

    os.makedirs("Scripts", exist_ok=True)

    # Copy if necessary
    if os.path.abspath(excel_path) != os.path.abspath(default_path):
        if not os.path.exists(excel_path):
            raise FileNotFoundError(f"Excel file not found: {excel_path}")
        shutil.copyfile(excel_path, default_path)
        print(f"Copied '{excel_path}' → '{default_path}'")
    else:
        print("Using existing Scripts/DRT.xlsx (no copy needed).")

    # Load Excel
    try:
        df = pd.read_excel(default_path, header=None)
    except Exception as e:
        raise RuntimeError(f"ERROR reading Excel file: {e}")

    # --------------------------------------------
    # Determine correct orbital columns from row 2
    # --------------------------------------------
    row3 = df.iloc[2]  # third row

    col_indices = []
    for col in range(2, len(row3)):  # start at 3rd column
        if pd.notna(row3[col]) and str(row3[col]).strip() != "":
            col_indices.append(col)

    if len(col_indices) == 0:
        raise RuntimeError("ERROR: No valid orbital columns found in 3rd row.")

    print(f"Detected orbital columns: {col_indices}")

    # --------------------------------------------
    # Extract fixed-location values
    # --------------------------------------------
    try:
        point_group = extract_point_group(df.iloc[0, 0])
        num_electrons = int(df.iloc[18, 2])
        multiplicity = df.iloc[18, 1]
        spin_state = extract_spin_from_multiplicity(multiplicity)
        spatial_symmetry = extract_symmetry(df.iloc[18, 3])
        num_unique_atoms = int(df.iloc[18, 4])

        # Orbital vectors
        scf_docc   = parse_row_values(df.iloc[3],  col_indices)
        scf_opsh   = parse_row_values(df.iloc[4],  col_indices)
        mcscf_docc = parse_row_values(df.iloc[5],  col_indices)
        mcscf_cas  = parse_row_values(df.iloc[7],  col_indices)
        mrci_fc    = parse_row_values(df.iloc[9],  col_indices)
        mrci_fv    = parse_row_values(df.iloc[10], col_indices)
        mrci_docc  = parse_row_values(df.iloc[11], col_indices)
        mrci_aux   = parse_row_values(df.iloc[13], col_indices)
        mrci_int   = parse_row_values(df.iloc[14], col_indices)

    except Exception as e:
        raise RuntimeError(f"ERROR: Could not read required values: {e}")

    # --------------------------------------------
    # Build output text
    # --------------------------------------------
    out_lines = []
    out_lines.append("#======================")
    out_lines.append("# INPUT VALUES")
    out_lines.append("#======================")
    out_lines.append(f"set num_unique_atoms {num_unique_atoms}")
    out_lines.append(f'set group_symmetry "{point_group}"')
    out_lines.append(f"set spatial_symmetry {spatial_symmetry}")
    out_lines.append("")
    out_lines.append("# FROM DRT TABLE")
    out_lines.append("#===========================")
    out_lines.append(f'set spin_state "{spin_state}"')
    out_lines.append(f"set num_electrons {num_electrons}")
    out_lines.append(f'set scf_docc "{scf_docc}"')
    out_lines.append(f'set scf_opsh "{scf_opsh}"')
    out_lines.append(f'set mcscf_docc "{mcscf_docc}"')
    out_lines.append(f'set mcscf_cas "{mcscf_cas}"')
    out_lines.append(f'set mrci_fc "{mrci_fc}"')
    out_lines.append(f'set mrci_fv "{mrci_fv}"')
    out_lines.append(f'set mrci_docc "{mrci_docc}"')
    out_lines.append(f'set mrci_aux "{mrci_aux}"')
    out_lines.append(f'set mrci_int "{mrci_int}"')

    output_text = "\n".join(out_lines)

    # --------------------------------------------
    # Write output
    # --------------------------------------------
    output_path = "Scripts/input_values.txt"
    with open(output_path, "w") as f:
        f.write(output_text)

    print("\nParsing complete!")
    print(f"Output written to {output_path}")


if __name__ == "__main__":
    main()


# -------------------------
# End of file
