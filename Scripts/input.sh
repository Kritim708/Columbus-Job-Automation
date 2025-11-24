#!/bin/bash

# Output file
OUTPUT_FILE="input_values.txt"

echo "Generating input values file..."

echo "#======================"
echo "# INPUT VALUES"
echo "#======================"

# Number of unique atoms
read -p "Enter number of elements: " num_unique_atoms

# Calculation set (cc-pvdz=1, cc-pvtz=6)
#echo "Select calculation set:"
#echo "1) cc-pvdz"
#echo "6) cc-pvtz"
#read -p "Enter set number: " calculation_set

# Group symmetry
read -p "Enter group symmetry (e.g., cs, c2v): " group_symmetry

# Spatial symmetry
read -p "Enter spatial symmtery " spatial_symmetry

#echo "#==========================="
#echo "# SINGLET VS TRIPLET VALUES"
#echo "#==========================="

#echo "Select multiplicity:"
#echo "1) Singlet"
#echo "3) Triplet"
#read -p "Enter multiplicity number (1 or 3): " singlet_triplet_num

# Determine high spin based on multiplicity
#if [ "$singlet_triplet_num" -eq 1 ]; then
#    high_spin="no"
#else
#    high_spin="yes"
#fi

echo "#==========================="
echo "# FROM DRT TABLE"
echo "#==========================="

read -p "Enter number of electrons: " num_electrons
read -p "Enter SCF doubly occupied orbitals (e.g., '9 2 7 1'): " scf_docc
read -p "Enter SCF open-shell orbitals (e.g., '2 0 0 0'): " scf_opsh
read -p "Enter MCSCF doubly occupied orbitals (e.g., '8 2 6 1'): " mcscf_docc
read -p "Enter MCSCF active space (e.g., '3 0 1 0'): " mcscf_cas
read -p "Enter MRCI frozen core (e.g., '4 0 2 0'): " mrci_fc
read -p "Enter MRCI frozen virtual (e.g., '0 0 0 0'): " mrci_fv
read -p "Enter MRCI doubly occupied orbitals (e.g., '4 2 4 1'): " mrci_docc
#read -p "Enter MRCI active orbitals (e.g., '3 0 1 0'): " mrci_act
read -p "Enter MRCI auxiliary orbitals (e.g., '0 0 0 0'): " mrci_aux
read -p "Enter MRCI internal orbitals (e.g., '7 2 5 1'): " mrci_int



#======================
# Write to file
#======================

{
echo "#======================"
echo "# INPUT VALUES"
echo "#======================"
echo "set num_unique_atoms $num_unique_atoms"
#echo "set calculation_set $calculation_set"
echo "set group_symmetry \"$group_symmetry\""
echo "set spatial_symmetry $spatial_symmetry"
echo ""
#echo "# SINGLET VS TRIPLET VALUES"
#echo "#==========================="
#echo "set singlet_triplet_num $singlet_triplet_num"
#echo "set high_spin $high_spin"
#echo ""
echo "# FROM DRT TABLE"
echo "#==========================="
echo "set num_electrons $num_electrons"
echo "set scf_docc \"$scf_docc\""
echo "set scf_opsh \"$scf_opsh\""
echo "set mcscf_docc \"$mcscf_docc\""
echo "set mcscf_cas \"$mcscf_cas\""
echo "set mrci_fc \"$mrci_fc\""
echo "set mrci_fv \"$mrci_fv\""
echo "set mrci_docc \"$mrci_docc\""
#echo "set mrci_act \"$mrci_act\""
echo "set mrci_aux \"$mrci_aux\""
echo "set mrci_int \"$mrci_int\""
} > "$OUTPUT_FILE"

echo "All inputs saved to $OUTPUT_FILE"

