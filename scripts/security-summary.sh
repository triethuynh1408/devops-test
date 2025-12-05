#!/usr/bin/env bash
set -euo pipefail

echo "Parsing SARIF and generating security summary per scanner..."

# SARIF files
SEM_GREP_SARIF="semgrep.sarif"
TRIVY_IMAGE_SARIF="trivy-image.sarif"
TRIVY_FS_SARIF="trivy-fs.sarif"
GITLEAKS_SARIF="gitleaks.sarif"

# ------------------------------------------------------------------------------
# Helper: count severity across SARIF formats
# ------------------------------------------------------------------------------
count_severity() {
    local file=$1
    local severity=$2

    if [[ ! -f "$file" ]]; then
        echo 0
        return
    fi

    jq --arg sev "$severity" '
      if (.runs // empty) then
        .runs[]
        | (.results // [])
        | map(
            # Semgrep → level = error/warning
            if ((.level // "" | ascii_upcase) == $sev) then 1

            # Trivy → properties.tags contains severity
            elif (.properties.tags // [] | map(ascii_upcase) | index($sev)) != null then 1

            # Gitleaks → properties.severity
            elif ((.properties.severity // "" | ascii_upcase) == $sev) then 1

            else 0
            end
        )
        | add
      else
        0
      end
    ' "$file" 2>/dev/null || echo 0
}

# ------------------------------------------------------------------------------
# Collect severity counts per tool
# ------------------------------------------------------------------------------
declare -A TRIVY_IMAGE TRIVY_FS SEMGREP GITLEAKS

for sev in CRITICAL HIGH MEDIUM LOW; do
    TRIVY_IMAGE[$sev]=$(count_severity "$TRIVY_IMAGE_SARIF" "$sev")
    TRIVY_FS[$sev]=$(count_severity "$TRIVY_FS_SARIF" "$sev")
    SEMGREP[$sev]=$(count_severity "$SEM_GREP_SARIF" "$([ "$sev" = "CRITICAL" ] && echo "ERROR" || [ "$sev" = "HIGH" ] && echo "WARNING" || echo "$sev")")
    GITLEAKS[$sev]=$(count_severity "$GITLEAKS_SARIF" "$sev")
done

# ------------------------------------------------------------------------------
# Generate summary markdown
# ------------------------------------------------------------------------------
OUTPUT="scanner-security-summary.md"

{
echo "## 🔐 Security Summary per Scanner"
echo ""

# Function to print table per tool
print_table() {
    local name=$1
    declare -n counts=$2

    echo "### $name"
    echo "| Severity | Count |"
    echo "|---------|-------|"
    echo "| 🔴 Critical | ${counts[CRITICAL]} |"
    echo "| 🟠 High     | ${counts[HIGH]} |"
    echo "| 🟡 Medium   | ${counts[MEDIUM]} |"
    echo "| 🟢 Low      | ${counts[LOW]} |"
    echo ""
}

print_table "Trivy Image Scan" TRIVY_IMAGE
print_table "Trivy Filesystem Scan" TRIVY_FS
print_table "Semgrep SAST" SEMGREP
print_table "Gitleaks Secret Scan" GITLEAKS

echo "> Generated from SARIF results of each scanner."
} > "$OUTPUT"

echo "Summary generated → $OUTPUT"

# ------------------------------------------------------------------------------
# Publish to GitHub Actions UI if available
# ------------------------------------------------------------------------------
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "Publishing summary to GitHub Actions UI..."
    cat "$OUTPUT" >> "$GITHUB_STEP_SUMMARY"
else
    echo "GITHUB_STEP_SUMMARY not detected (running locally)."
fi
