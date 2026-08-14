#!/bin/bash

# This script checks for illegal cross-repository relative links in sub-directory READMEs.
# Relative links starting with "../" are not allowed in sub-directory READMEs because 
# these directories are published as independent repositories.

set -e

EXIT_CODE=0

# Define sub-directories that are published as independent repositories
SUB_REPOS=("HRPAuth" "HASkinLib" "WinnerProxy" "HASkinProxy" "HRPAuth-WebUI")

echo "Checking for illegal relative links in sub-repository READMEs..."

for repo in "${SUB_REPOS[@]}"; do
    README="$repo/README.md"
    if [ -f "$README" ]; then
        # Search for patterns like ](../ or ](./../
        INVALID_LINKS=$(grep -nE "\]\(\.\./" "$README" || true)
        
        if [ -n "$INVALID_LINKS" ]; then
            echo "❌ Error: Found illegal relative links in $README:"
            echo "$INVALID_LINKS"
            EXIT_CODE=1
        else
            echo "✅ $README is clean."
        fi
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo "All sub-repository READMEs passed the link check."
else
    echo "Check failed. Please use absolute URLs for cross-repository documentation links."
fi

exit $EXIT_CODE
