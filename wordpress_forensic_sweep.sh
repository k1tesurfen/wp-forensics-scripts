#!/usr/bin/env bash

# =====================================================
# WordPress Forensic Sweep Script (Adjusted)
# Skips core files if checksums pass
# =====================================================

SITE_PATH=${1:-$(pwd)}
REPORT="wp_forensic_report_$(date +%Y%m%d_%H%M%S).txt"

cd "$SITE_PATH" || exit 1

echo "Starting WordPress forensic sweep..."
echo "Site path: $SITE_PATH"
echo "Report: $REPORT"
echo ""

{
  echo "================================================="
  echo "WordPress Forensic Sweep Report"
  echo "================================================="
  echo "Date: $(date)"
  echo "Path: $SITE_PATH"
  echo ""

  # ------------------------------------------------
  echo "1. WordPress Core Checksum Verification"
  echo "------------------------------------------------"

  CORE_CLEAN=0
  if command -v wp >/dev/null; then
    VERIFY_OUTPUT=$(wp core verify-checksums 2>&1)
    echo "$VERIFY_OUTPUT"
    if echo "$VERIFY_OUTPUT" | grep -qi "Success: WordPress installation verifies"; then
      CORE_CLEAN=1
      echo ""
      echo "✅ Core files clean. Skipping core directory scans."
    else
      echo ""
      echo "⚠️ Core files modified. Scanning entire tree for suspicious PHP."
    fi
  else
    echo "WP-CLI not installed. Cannot verify checksums."
    echo "Will scan entire tree."
  fi
  echo ""

  # ------------------------------------------------
  echo "2. Suspicious PHP functions scan"
  echo "------------------------------------------------"

  # Decide scan path
  if [ $CORE_CLEAN -eq 1 ]; then
    SCAN_PATH="wp-content"
  else
    SCAN_PATH="."
  fi

  grep -R --line-number --color=never \
    -e "base64_decode(" \
    -e "eval(" \
    -e "gzinflate(" \
    -e "str_rot13(" \
    -e "assert(" \
    -e "shell_exec(" \
    -e "system(" \
    -e "passthru(" \
    -e "exec(" \
    -e "preg_replace.*\/e" "$SCAN_PATH" 2>/dev/null
  echo ""

  # ------------------------------------------------
  echo "3. PHP files inside uploads directory"
  echo "------------------------------------------------"
  find wp-content/uploads -type f -name "*.php" 2>/dev/null
  echo ""

  # ------------------------------------------------
  echo "4. Hidden PHP files"
  echo "------------------------------------------------"
  find . -type f -name ".*.php"
  echo ""

  # ------------------------------------------------
  echo "5. Recently modified files (last 7 days)"
  echo "------------------------------------------------"
  find . -type f -mtime -7 -print
  echo ""

  # ------------------------------------------------
  echo "6. Plugin directory listing"
  echo "------------------------------------------------"
  ls -lah wp-content/plugins
  echo ""

  # ------------------------------------------------
  echo "7. WordPress Cron Jobs"
  echo "------------------------------------------------"
  if command -v wp >/dev/null; then
    wp cron event list 2>&1
  else
    echo "WP-CLI not available"
  fi
  echo ""

  # ------------------------------------------------
  echo "8. Administrator accounts"
  echo "------------------------------------------------"
  if command -v wp >/dev/null; then
    wp user list --role=administrator 2>&1
  else
    echo "WP-CLI not available"
  fi
  echo ""

  # ------------------------------------------------
  echo "9. Database autoload size"
  echo "------------------------------------------------"
  if command -v wp >/dev/null; then
    wp db query "SELECT SUM(LENGTH(option_value))/1024/1024 AS autoload_mb FROM wp_options WHERE autoload='yes';" 2>&1
  else
    echo "WP-CLI not available"
  fi
  echo ""

  # ------------------------------------------------
  echo "10. Potential remote network calls"
  echo "------------------------------------------------"
  grep -R --line-number --color=never \
    -e "curl_exec(" \
    -e "file_get_contents(\"http" \
    -e "fsockopen(" \
    -e "pfsockopen(" "$SCAN_PATH" 2>/dev/null
  echo ""

  # ------------------------------------------------
  echo "11. .htaccess inspection"
  echo "------------------------------------------------"
  if [ -f ".htaccess" ]; then
    cat .htaccess
  else
    echo "No .htaccess file found"
  fi
  echo ""

  # ------------------------------------------------
  echo "12. Suspicious file names"
  echo "------------------------------------------------"
  find . -type f \( \
    -name "*cache*.php" -o \
    -name "*tmp*.php" -o \
    -name "*shell*.php" -o \
    -name "*seo*.php" -o \
    -name "*inject*.php" \
    \)
  echo ""

  # ------------------------------------------------
  echo "13. PHP session usage"
  echo "------------------------------------------------"
  grep -R "session_start(" "$SCAN_PATH" 2>/dev/null
  echo ""

  # ------------------------------------------------
  echo "14. Large files (potential payloads)"
  echo "------------------------------------------------"
  find . -type f -size +5M
  echo ""

  echo "================================================="
  echo "End of forensic sweep"
  echo "================================================="

} >"$REPORT"

echo ""
echo "Sweep finished."
echo "Report saved to:"
echo "$REPORT"
echo ""
