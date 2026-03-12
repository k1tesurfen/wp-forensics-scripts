#!/usr/bin/env bash

# ============================================
# WordPress / Server TTFB Diagnostic Script
# Generates a technical diagnostic report
# ============================================

set -e # Exit immediately if a command exits with a non-zero status

# Default variables
LANG_DE=false
DOMAIN=""
STATIC_PATH=""

# -----------------------------
# Usage & Help
# -----------------------------
usage() {
  echo "Usage: $0 -d <domain> -s <static_path> [-g]"
  echo ""
  echo "Required Arguments:"
  echo "  -d, --domain      The target domain (e.g., https://example.com)"
  echo "  -s, --static      Path to a static resource (e.g., /wp-content/uploads/image.jpg)"
  echo ""
  echo "Optional Arguments:"
  echo "  -g, --german      Generate the report in German (English is default)"
  echo "  -h, --help        Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 -d https://mywebsite.com -s /wp-content/uploads/2023/10/logo.png"
}

# -----------------------------
# Argument Parsing
# -----------------------------
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -d | --domain)
    DOMAIN="$2"
    shift
    ;;
  -s | --static)
    STATIC_PATH="$2"
    shift
    ;;
  -g | --german) LANG_DE=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Error: Unknown parameter passed: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# -----------------------------
# Input Validation
# -----------------------------
if [[ -z "$DOMAIN" || -z "$STATIC_PATH" ]]; then
  echo "Error: Both domain (-d) and static resource path (-s) are required."
  echo ""
  usage
  exit 1
fi

# Ensure domain starts with http:// or https://
if [[ ! "$DOMAIN" =~ ^https?:// ]]; then
  DOMAIN="https://$DOMAIN"
fi

# Ensure static path starts with /
if [[ ! "$STATIC_PATH" =~ ^/ ]]; then
  STATIC_PATH="/$STATIC_PATH"
fi

# Remove trailing slash from domain if present to avoid double slashes
DOMAIN="${DOMAIN%/}"

# Check for required tools
for cmd in curl awk; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed. Please install it and try again."
    exit 1
  fi
done

# -----------------------------
# Test Execution
# -----------------------------
RANDOM_FILE="diagnose_test_$(date +%s)"
REPORT_TIME=$(date +%Y%m%d_%H%M%S)

if [ "$LANG_DE" = true ]; then
  REPORT="diagnosebericht_${REPORT_TIME}.txt"
  echo "Starte Diagnose für $DOMAIN ..."
else
  REPORT="diagnostic_report_${REPORT_TIME}.txt"
  echo "Starting diagnostics for $DOMAIN ..."
fi
echo ""

measure_ttfb() {
  curl -o /dev/null -s -w "%{time_starttransfer}" "$1"
}

measure_breakdown() {
  curl -w "
DNS: %{time_namelookup}
Connect: %{time_connect}
TLS: %{time_appconnect}
Pretransfer: %{time_pretransfer}
TTFB: %{time_starttransfer}
" -o /dev/null -s "$1"
}

TTFB_MAIN=$(measure_ttfb "$DOMAIN")
TTFB_STATIC=$(measure_ttfb "$DOMAIN$STATIC_PATH")
TTFB_FAKE=$(measure_ttfb "$DOMAIN/$RANDOM_FILE")

BREAKDOWN=$(measure_breakdown "$DOMAIN")
HEADERS=$(curl -I -s "$DOMAIN")

# Convert to integer (1 if > 2 seconds, else 0) using awk for broader compatibility
MAIN_INT=$(echo "$TTFB_MAIN" | awk '{if ($1 > 2) print 1; else print 0}')
STATIC_INT=$(echo "$TTFB_STATIC" | awk '{if ($1 > 2) print 1; else print 0}')
FAKE_INT=$(echo "$TTFB_FAKE" | awk '{if ($1 > 2) print 1; else print 0}')

# -----------------------------
# Report Generation
# -----------------------------
{
  if [ "$LANG_DE" = true ]; then
    # GERMAN REPORT
    echo "==============================================="
    echo "Technischer Diagnosebericht – Webserver / TTFB"
    echo "==============================================="
    echo "Zielsystem: $DOMAIN"
    echo "Datum: $(date)"
    echo ""
    echo "------------------------------------------------"
    echo "1. Hintergrund"
    echo "------------------------------------------------"
    echo "Die Seite zeigte potenziell hohe Time-To-First-Byte (TTFB) Zeiten."
    echo "Ziel dieser Tests ist es festzustellen, ob die Verzögerung"
    echo "durch WordPress/PHP, Netzwerkprobleme oder den Webserver"
    echo "(Apache/Nginx) selbst verursacht wird."
    echo ""
    echo "------------------------------------------------"
    echo "2. Testergebnisse"
    echo "------------------------------------------------"
    echo "Test 1: Basis TTFB (Hauptseite)"
    echo "Ergebnis: $TTFB_MAIN Sekunden"
    echo ""
    echo "Test 2: Statische Datei (Umgeht PHP/WordPress)"
    echo "URL: $DOMAIN$STATIC_PATH"
    echo "Ergebnis: $TTFB_STATIC Sekunden"
    echo ""
    echo "Test 3: Nicht existierende Datei (Erzwingt 404)"
    echo "Ergebnis: $TTFB_FAKE Sekunden"
    echo ""
    echo "Test 4: Netzwerk-Timing Breakdown"
    echo "$BREAKDOWN"
    echo ""
    echo "------------------------------------------------"
    echo "3. Interpretation der Ergebnisse"
    echo "------------------------------------------------"
    if [ "$STATIC_INT" -eq 1 ] && [ "$FAKE_INT" -eq 1 ]; then
      echo "ACHTUNG: Statische Dateien und nicht existierende URLs"
      echo "benötigen ebenfalls mehrere Sekunden für das erste Byte."
      echo ""
      echo "Das deutet stark darauf hin, dass die Verzögerung NICHT durch"
      echo "WordPress oder PHP verursacht wird, sondern auf Serverebene liegt."
      echo ""
      echo "Wahrscheinliche Ursachen:"
      echo "- Webserver Worker Limit erreicht (z.B. Apache MaxRequestWorkers, Nginx worker_connections)"
      echo "- CPU Throttling auf Shared Hosting"
      echo "- Strikte Web Application Firewall (WAF) oder Malware-Scanner"
      echo "- Überlastete Festplatten (hoher IO-Wait)"
    else
      echo "Die Werte für statische/404 Anfragen sind im Rahmen."
      echo "Die Verzögerung entsteht höchstwahrscheinlich in der"
      echo "Anwendungsschicht (PHP, Datenbank oder komplexe WordPress-Plugins)."
    fi
    echo ""
    echo "------------------------------------------------"
    echo "4. Weitere sinnvolle Checks auf dem Server"
    echo "------------------------------------------------"
    echo "Serverlast:          top oder htop"
    echo "Disk I/O:            iostat -x 1"
    echo "PHP-FPM Logs:        tail -f /var/log/php-fpm/www-error.log"
    echo "WP Autoload Größe:   SELECT SUM(LENGTH(option_value)) FROM wp_options WHERE autoload='yes';"
    echo ""
    echo "Ende des Reports."

  else
    # ENGLISH REPORT
    echo "==============================================="
    echo "Technical Diagnostic Report – Web Server / TTFB"
    echo "==============================================="
    echo "Target System: $DOMAIN"
    echo "Date: $(date)"
    echo ""
    echo "------------------------------------------------"
    echo "1. Background"
    echo "------------------------------------------------"
    echo "The site potentially showed high Time-To-First-Byte (TTFB) times."
    echo "The goal of these tests is to determine if the delay is caused"
    echo "by WordPress/PHP, network constraints, or the web server"
    echo "(Apache/Nginx) itself."
    echo ""
    echo "------------------------------------------------"
    echo "2. Test Results"
    echo "------------------------------------------------"
    echo "Test 1: Base TTFB (Main Page)"
    echo "Result: $TTFB_MAIN seconds"
    echo ""
    echo "Test 2: Static File (Bypasses PHP/WordPress)"
    echo "URL: $DOMAIN$STATIC_PATH"
    echo "Result: $TTFB_STATIC seconds"
    echo ""
    echo "Test 3: Non-existent File (Forces 404)"
    echo "Result: $TTFB_FAKE seconds"
    echo ""
    echo "Test 4: Network Timing Breakdown"
    echo "$BREAKDOWN"
    echo ""
    echo "------------------------------------------------"
    echo "3. Result Interpretation"
    echo "------------------------------------------------"
    if [ "$STATIC_INT" -eq 1 ] && [ "$FAKE_INT" -eq 1 ]; then
      echo "WARNING: Static files and non-existent URLs also"
      echo "take multiple seconds to deliver the first byte."
      echo ""
      echo "This strongly indicates that the delay is NOT caused by"
      echo "WordPress or PHP, but rather at the server infrastructure level."
      echo ""
      echo "Probable Causes:"
      echo "- Web server worker limits reached (e.g., Apache MaxRequestWorkers, Nginx worker_connections)"
      echo "- CPU Throttling on Shared Hosting environments"
      echo "- Aggressive Web Application Firewall (WAF) or security scanners"
      echo "- Overloaded storage drives (High IO-Wait)"
    else
      echo "The metrics for static and 404 requests look normal."
      echo "The delay is highly likely occurring at the application layer"
      echo "(PHP execution, slow database queries, or heavy WordPress plugins)."
    fi
    echo ""
    echo "------------------------------------------------"
    echo "4. Further Recommended Checks"
    echo "------------------------------------------------"
    echo "Server Load:         top or htop"
    echo "Disk I/O:            iostat -x 1"
    echo "PHP-FPM Logs:        tail -f /var/log/php-fpm/www-error.log"
    echo "WP Autoload Size:    SELECT SUM(LENGTH(option_value)) FROM wp_options WHERE autoload='yes';"
    echo ""
    echo "End of Report."
  fi
} >"$REPORT"

if [ "$LANG_DE" = true ]; then
  echo "Diagnose abgeschlossen."
  echo "Report gespeichert unter: $REPORT"
else
  echo "Diagnostics complete."
  echo "Report saved to: $REPORT"
fi
echo ""
