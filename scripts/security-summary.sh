#!/bin/bash
set -euo pipefail

echo "Parsing SARIF and generating combined summary..."

# ======================================================
# Helper: Extract severity counts
# ======================================================
count_severity () {
  local FILE=$1
  local SEVERITY=$2

  jq -r \
    --arg sev "$SEVERITY" '
      [
        .runs[].results[]
        | try (.properties["security-severity"] // .level // "")
        | ascii_upcase
      ]
      | map(select(contains($sev)))
      | length
    ' "$FILE"
}

count_sarif_by_level () {
  local FILE=$1
  local LEVEL=$2

  jq --arg lvl "$LEVEL" '
    [
      .runs[].results[] | select(.level == $lvl)
    ] | length
  ' "$FILE"
}

# =============== TRIVY FS ===============
TRIVY_FS_CRIT=$(count_severity trivy-fs.sarif "CRITICAL")
TRIVY_FS_HIGH=$(count_severity trivy-fs.sarif "HIGH")
TRIVY_FS_MED=$(count_severity trivy-fs.sarif "MEDIUM")
TRIVY_FS_LOW=$(count_severity trivy-fs.sarif "LOW")

# =============== TRIVY IMAGE ===============
TRIVY_IMG_CRIT=$(count_severity trivy-image.sarif "CRITICAL")
TRIVY_IMG_HIGH=$(count_severity trivy-image.sarif "HIGH")
TRIVY_IMG_MED=$(count_severity trivy-image.sarif "MEDIUM")
TRIVY_IMG_LOW=$(count_severity trivy-image.sarif "LOW")

# =============== GITLEAKS ===============
GITLEAKS_CRIT=$(count_severity gitleaks.sarif "CRITICAL")
GITLEAKS_HIGH=$(count_severity gitleaks.sarif "HIGH")
GITLEAKS_MED=$(count_severity gitleaks.sarif "MEDIUM")
GITLEAKS_LOW=$(count_severity gitleaks.sarif "LOW")

# =============== SEMGREP ===============
SEMGREP_ERRORS=$(count_sarif_by_level semgrep.sarif "error")
SEMGREP_WARNINGS=$(count_sarif_by_level semgrep.sarif "warning")
SEMGREP_NOTES=$(count_sarif_by_level semgrep.sarif "note")

SEMGREP_HIGH=$SEMGREP_ERRORS
SEMGREP_MEDIUM=$SEMGREP_WARNINGS
SEMGREP_LOW=$SEMGREP_NOTES

# ==========================
# Build Markdown Summary
# ==========================
{
  echo "## 🔐 Unified Security Scan Summary"
  echo ""

  echo "---"
  echo "### 🧨 Trivy Filesystem Scan"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| Critical | $TRIVY_FS_CRIT |"
  echo "| High     | $TRIVY_FS_HIGH |"
  echo "| Medium   | $TRIVY_FS_MED |"
  echo "| Low      | $TRIVY_FS_LOW |"
  echo ""

  echo "---"
  echo "### 🐳 Trivy Image Scan"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| Critical | $TRIVY_IMG_CRIT |"
  echo "| High     | $TRIVY_IMG_HIGH |"
  echo "| Medium   | $TRIVY_IMG_MED |"
  echo "| Low      | $TRIVY_IMG_LOW |"
  echo ""

  echo "---"
  echo "### 🔑 Gitleaks Secret Scan"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| Critical | $GITLEAKS_CRIT |"
  echo "| High     | $GITLEAKS_HIGH |"
  echo "| Medium   | $GITLEAKS_MED |"
  echo "| Low      | $GITLEAKS_LOW |"
  echo ""

  echo "---"
  echo "### 🛡️ Semgrep (SAST)"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| High     | $SEMGREP_HIGH |"
  echo "| Medium   | $SEMGREP_MEDIUM |"
  echo "| Low      | $SEMGREP_LOW |"
  echo ""

  echo "---"
  echo "Generated automatically from SARIF results."
} >> "$GITHUB_STEP_SUMMARY"
