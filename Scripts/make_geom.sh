#!/bin/bash
# This script converts ONE xyz file to Columbus geometry format

# Load Columbus
#module load columbus/722

# Columbus root must be defined externally
#if [ -z "$COLUMBUS" ]; then
#    echo "❌ ERROR: COLUMBUS environment variable not set."
#    exit 1
#fi

# Required argument: filename
INPUT_FILE="$1"
COLUMBUS=${2}


if [ -z "$INPUT_FILE" ]; then
    echo "❌ ERROR: No input .xyz file provided."
    exit 1
fi

# Resolve full path relative to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FULL_PATH="$SCRIPT_DIR/$INPUT_FILE"

if [ ! -f "$FULL_PATH" ]; then
    echo "❌ ERROR: File not found: $FULL_PATH"
    exit 1
fi

echo "Processing xyz file: $FULL_PATH"

# Run xyz2col.x
"$COLUMBUS/xyz2col.x" < "$FULL_PATH"

echo "Done."


