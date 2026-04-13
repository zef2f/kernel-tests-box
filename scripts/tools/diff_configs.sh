#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

# diff_configs.sh - Compares two Linux kernel config files and outputs the
# differences found in the second file that are not present or differ in the first.
# This is useful for creating a 'config fragment' (overlay).

# Set script name for usage
SCRIPT_NAME=$(basename "$0")

# Function to display usage information
usage() {
    echo "Usage: $SCRIPT_NAME <config_file_1> <config_file_2>"
    echo ""
    echo "Outputs the configuration lines that differ between the two files,"
    echo "using the values from <config_file_2>."
    echo "The output is a config fragment suitable for merging."
}

# Check if two arguments were provided
if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi

CONFIG_1=$1
CONFIG_2=$2

# Check if files exist
if [ ! -f "$CONFIG_1" ] || [ ! -f "$CONFIG_2" ]; then
    echo "Error: Both files must exist."
    usage
    exit 1
fi

# 1. Clean and normalize the config files for reliable comparison.
# This removes empty lines and unnecessary comments, except for the
# '# CONFIG_... is not set' lines, which are configuration options themselves.

# Filter and process config.1
# - Remove lines starting with just '#' (comments/headers)
# - Remove empty lines
# - Store the clean output in a temporary file
TMP_1=$(mktemp)
grep -v "^#" "$CONFIG_1" | grep -v "^$" > "$TMP_1"

# Filter and process config.2
# - Remove lines starting with just '#' (comments/headers)
# - Remove empty lines
TMP_2=$(mktemp)
grep -v "^#" "$CONFIG_2" | grep -v "^$" > "$TMP_2"


# 2. Use 'diff' to find all differing lines, then filter for lines specific to CONFIG_2.
# 'diff' output flags:
# - '> ' indicates a line only present in file 2 (or a line that replaced a differing line from file 1).

# Use diff to compare the cleaned config files.
# The core logic:
# - Compare the two cleaned files.
# - Filter the output to only show lines starting with '> ' (lines unique to or changed in CONFIG_2).
# - Strip the '> ' prefix to get the raw config line.

diff --changed-group-format='%>' --unchanged-group-format='' "$TMP_1" "$TMP_2" | grep -v "^$"

# 3. Clean up temporary files
rm -f "$TMP_1" "$TMP_2"

exit 0
