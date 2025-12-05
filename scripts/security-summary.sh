#!/usr/bin/env bash
set -euo pipefail

echo "Parsing SARIF and generating combined summary..."

# ---------------------------
# Helper: safe JQ check
# ---------------------------
safe_jq() {
  local FILE=$1
  jq empty "$FILE" 2>/dev/null || { echo "Invalid SARIF: $FILE"; return 1; }
}

# ---------------------------
# Helper: count severity
# ---------------------------
count_severity() {
  local FILE=$1
  local SEVERITY=$2

  jq -r --arg sev "$SEVERITY" '
    [
      .runs[].results[]
      | (
          # Trivy: uses properties.tags[] for severity
          (try .properties.tags[] catch "") |

          # Semgrep and Gitleaks: use .level
          (try .level catch "")
        )
        | ascii_upcase
        | select(contains($sev))
    ] | length
  ' "$FILE"
}

# Validate JSON
safe_jq trivy-fs.sarif
safe_jq trivy-image.sarif
safe_jq gitleaks.sarif
safe_jq semgrep.sarif

# TRIVY severity detection
TRIVY_FS_CRIT=$(count_severity trivy-fs.sarif "CRITICAL")
TRIVY_FS_HIGH=$(count_severity trivy-fs.sarif "HIGH")
TRIVY_FS_MED=$(count_severity trivy-fs.sarif "MEDIUM")
TRIVY_FS_LOW=$(count_severity trivy-fs.sarif "LOW")

TRIVY_IMG_CRIT=$(count_severity trivy-image.sarif "CRITICAL")
TRIVY_IMG_HIGH=$(count_severity trivy-image.sarif "HIGH")
TRIVY_IMG_MED=$(count_severity trivy-image.sarif "MEDIUM")
TRIVY_IMG_LOW=$(count_severity trivy-image.sarif "LOW")

# GITLEAKS—map any .level="error" to HIGH
GITLEAKS_HIGH=$(count_severity gitleaks.sarif "ERROR")
GITLEAKS_MED=$(count_severity gitleaks.sarif "WARNING")
GITLEAKS_LOW=$(count_severity gitleaks.sarif "NOTE")

# SEMGREP
SEMGREP_HIGH=$(count_severity semgrep.sarif "ERROR")
SEMGREP_MED=$(count_severity semgrep.sarif "WARNING")
SEMGREP_LOW=$(count_severity semgrep.sarif "NOTE")

# OUTPUT
{
  echo "## 🔐 Security Scan Summary"
  echo "---"

  echo "### 🧨 Trivy FS Scan"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| Critical | $TRIVY_FS_CRIT |"
  echo "| High     | $TRIVY_FS_HIGH |"
  echo "| Medium   | $TRIVY_FS_MED |"
  echo "| Low      | $TRIVY_FS_LOW |"
  echo ""

  echo "### 🐳 Trivy Image Scan"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| Critical | $TRIVY_IMG_CRIT |"
  echo "| High     | $TRIVY_IMG_HIGH |"
  echo "| Medium   | $TRIVY_IMG_MED |"
  echo "| Low      | $TRIVY_IMG_LOW |"
  echo ""

  echo "### 🔑 Gitleaks"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| High     | $GITLEAKS_HIGH |"
  echo "| Medium   | $GITLEAKS_MED |"
  echo "| Low      | $GITLEAKS_LOW |"
  echo ""

  echo "### 🛡️ Semgrep"
  echo "| Severity | Count |"
  echo "|----------|-------|"
  echo "| High     | $SEMGREP_HIGH |"
  echo "| Medium   | $SEMGREP_MED |"
  echo "| Low      | $SEMGREP_LOW |"
  echo ""

} >> "$GITHUB_STEP_SUMMARY"
