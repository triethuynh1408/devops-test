#!/bin/bash

# --- Configuration ---
TRIVY_FS_FILE="${GITHUB_WORKSPACE}/trivy-fs.sarif"
TRIVY_IMAGE_FILE="${GITHUB_WORKSPACE}/trivy-image.sarif"
GITLEAKS_FILE="${GITHUB_WORKSPACE}/gitleaks.sarif"
SEMGREP_FILE="${GITHUB_WORKSPACE}/semgrep.sarif"
OUTPUT_FILE="scan_summary_all.md"

# Severity order for reporting and indexing
SEVERITIES=("CRITICAL" "HIGH" "MEDIUM" "LOW")

# Initialize total counts (Indexed array: 0=CRITICAL, 1=HIGH, 2=MEDIUM, 3=LOW)
TOTAL_COUNTS=(0 0 0 0)
TOTAL_VULNS=0

# --- Utility Functions ---

# Maps the severity string to its index (0, 1, 2, 3)
get_severity_index() {
    local sev=$1
    case "$sev" in
        CRITICAL) echo 0 ;;
        HIGH) echo 1 ;;
        MEDIUM) echo 2 ;;
        LOW) echo 3 ;;
        *) echo -1 ;; # Unknown/Other
    esac
}

# Gets the value of a dynamic variable (e.g., get_var FS_HIGH)
get_var() {
    local var_name=$1
    echo "${!var_name}"
}

# --- Parsing Functions ---

## Function to process a Trivy SARIF file (vulnerabilities) - (Logic remains the same)
process_trivy_sarif() {
    local file=$1
    local prefix=$2
    local total=0
    
    if [ ! -f "$file" ]; then
        echo "Warning: Trivy file $file not found. Skipping." >&2
        return
    fi

    local FILE_COUNTS=(0 0 0 0)

    # Trivy logic: links result ruleId to rule properties.tags
    COUNTS=$(jq -r '
        .runs[0].tool.driver.rules as $rules |
        .runs[].results[]? | 
        .ruleId as $ruleId | 
        ($rules[]? | select(.id == $ruleId)) | 
        .properties.tags[]? | 
        select(IN(.; "CRITICAL", "HIGH", "MEDIUM", "LOW", "WARNING", "NOTE")) |
        ascii_upcase |
        if . == "WARNING" then "MEDIUM" 
        elif . == "NOTE" then "LOW" 
        else . 
        end
    ' "$file" | sort | uniq -c)
    
    while read -r count severity; do
        if [ -n "$severity" ]; then
            idx=$(get_severity_index "$severity")
            if [ "$idx" -ge 0 ]; then
                FILE_COUNTS[$idx]=$((FILE_COUNTS[$idx] + count))
                TOTAL_COUNTS[$idx]=$((TOTAL_COUNTS[$idx] + count))
                total=$((total + count))
            fi
        fi
    done <<< "$COUNTS"

    export ${prefix}_TOTAL=$total
    for i in 0 1 2 3; do
        export ${prefix}_${SEVERITIES[$i]}=${FILE_COUNTS[$i]}
    done
}

## Function to process a Gitleaks SARIF file (secrets) - (Logic remains the same)
process_gitleaks_sarif() {
    local file=$1
    local prefix=$2
    local total=0
    
    if [ ! -f "$file" ]; then
        echo "Warning: Gitleaks file $file not found. Skipping." >&2
        return
    fi
    
    local HIGH_INDEX=1
    local GITLEAKS_COUNT=0
    
    GITLEAKS_COUNT=$(jq -r '[.runs[].results[]? | select(. == {})] | length' "$file" || echo 0)

    if [ -n "$GITLEAKS_COUNT" ]; then
        GITLEAKS_COUNT=$((GITLEAKS_COUNT))
        total=$GITLEAKS_COUNT
        
        TOTAL_COUNTS[$HIGH_INDEX]=$((TOTAL_COUNTS[$HIGH_INDEX] + GITLEAKS_COUNT))
        
        export ${prefix}_TOTAL=$total
        export ${prefix}_CRITICAL=0
        export ${prefix}_HIGH=$GITLEAKS_COUNT
        export ${prefix}_MEDIUM=0
        export ${prefix}_LOW=0
    fi
}


## Function to process a Semgrep SARIF file (Code Analysis) - FIX APPLIED
process_semgrep_sarif() {
    local file=$1
    local prefix=$2
    local total=0
    
    if [ ! -f "$file" ]; then
        echo "Warning: Semgrep file $file not found. Skipping." >&2
        return
    fi

    local FILE_COUNTS=(0 0 0 0) # CRIT, HIGH, MED, LOW

    # Corrected jq query: Only includes actual code findings from .results[]
    COUNTS=$(jq -r '
        .runs[0].tool.driver.rules as $rules |
        (
            # 1. ONLY logic for actual code findings in .results[]
            .runs[].results[]? | 
            .ruleId as $ruleId | 
            ($rules[]? | select(.id == $ruleId)) | 
            .defaultConfiguration.level # <-- Uses level from rule definition
        ) |
        # Process and map all gathered levels
        ascii_upcase |
        if . == "ERROR" then "HIGH" 
        elif . == "WARNING" then "MEDIUM" 
        elif . == "NOTE" then "LOW"
        else "UNKNOWN"
        end
    ' "$file" | sort | uniq -c)
    
    while read -r count severity; do
        if [ -n "$severity" ] && [ "$severity" != "UNKNOWN" ]; then
            idx=$(get_severity_index "$severity")
            if [ "$idx" -ge 0 ]; then
                FILE_COUNTS[$idx]=$((FILE_COUNTS[$idx] + count))
                TOTAL_COUNTS[$idx]=$((TOTAL_COUNTS[$idx] + count))
                total=$((total + count))
            fi
        fi
    done <<< "$COUNTS"

    export ${prefix}_TOTAL=$total
    export ${prefix}_CRITICAL=${FILE_COUNTS[0]}
    export ${prefix}_HIGH=${FILE_COUNTS[1]}
    export ${prefix}_MEDIUM=${FILE_COUNTS[2]}
    export ${prefix}_LOW=${FILE_COUNTS[3]}
}


# --- Main Execution ---

# 1. Check Prerequisite
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. Please install it (e.g., sudo apt install jq)." >&2
    exit 1
fi

echo "Starting Unified SARIF analysis (Trivy, Gitleaks, Semgrep)..."

# 2. Process Files
process_trivy_sarif "$TRIVY_FS_FILE" "FS"
process_trivy_sarif "$TRIVY_IMAGE_FILE" "IMAGE"
process_gitleaks_sarif "$GITLEAKS_FILE" "GL"
process_semgrep_sarif "$SEMGREP_FILE" "SG" # <-- Call to the updated function

# 3. Calculate Grand Total
for count in "${TOTAL_COUNTS[@]}"; do
    TOTAL_VULNS=$((TOTAL_VULNS + count))
done

# --- Generate Markdown Output ---
{
    echo "# 🛡️ Unified Security Scan Summary"
    echo ""
    echo "**Date:** $(date +'%Y-%m-%d %H:%M:%S')"
    echo ""
    
    ## Overall Summary
    echo "## Overall Vulnerability Count"
    echo ""
    echo "| Severity | Count |"
    echo "| :--- | :--- |"
    
    for i in 0 1 2 3; do
        echo "| **${SEVERITIES[$i]}** | ${TOTAL_COUNTS[$i]} |"
    done
    
    echo "| **TOTAL** | **$TOTAL_VULNS** |"
    echo ""
    echo "---"

    ## Breakdown by Scan File
    echo "## Breakdown by Scan File"
    echo ""
    echo "### Trivy File (Filesystem): \`$TRIVY_FS_FILE\` (Total: $FS_TOTAL)"
    echo "| Severity | Count |"
    echo "| :--- | :--- |"
    for SEV in "${SEVERITIES[@]}"; do
        COUNT_VAR="FS_${SEV}"
        echo "| **$SEV** | $(get_var $COUNT_VAR) |"
    done
    
    echo ""
    echo "---"

    echo "### Trivy File (Image): \`$TRIVY_IMAGE_FILE\` (Total: $IMAGE_TOTAL)"
    echo "| Severity | Count |"
    echo "| :--- | :--- |"
    for SEV in "${SEVERITIES[@]}"; do
        COUNT_VAR="IMAGE_${SEV}"
        echo "| **$SEV** | $(get_var $COUNT_VAR) |"
    done
    
    echo ""
    echo "---"

    echo "### Gitleaks File (Secrets): \`$GITLEAKS_FILE\` (Total: $GL_TOTAL)"
    echo "(All secret leaks categorized as HIGH)"
    echo "| Severity | Count |"
    echo "| :--- | :--- |"
    for SEV in "${SEVERITIES[@]}"; do
        COUNT_VAR="GL_${SEV}"
        echo "| **$SEV** | $(get_var $COUNT_VAR) |"
    done

    echo ""
    echo "---"

    # Semgrep Breakdown
    echo "### Semgrep File (Code Analysis): \`$SEMGREP_FILE\` (Total: $SG_TOTAL)"
    echo "(Mapping: ERROR $\\rightarrow$ HIGH, WARNING $\\rightarrow$ MEDIUM, NOTE $\\rightarrow$ LOW. Includes tool warnings.)"
    echo "| Severity | Count |"
    echo "| :--- | :--- |"
    for SEV in "${SEVERITIES[@]}"; do
        COUNT_VAR="SG_${SEV}"
        echo "| **$SEV** | $(get_var $COUNT_VAR) |"
    done
    
} > "$OUTPUT_FILE"

echo "Analysis complete."
echo "Total vulnerabilities and secrets detected: $TOTAL_VULNS"
echo "Summary written to **$OUTPUT_FILE**"

# ------------------------------------------------------------------------------
# Write to GitHub Actions UI if available
# ------------------------------------------------------------------------------
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "Publishing summary to GitHub Actions UI..."
    cat "$OUTPUT_FILE" >> "$GITHUB_STEP_SUMMARY"
else
    echo "GITHUB_STEP_SUMMARY not detected (running locally)."
fi