#!/usr/bin/env bash
# SABnzbd post-processing script to extract ISO files and delete them
# Expected SABnzbd arguments (based on your log):
# $1 = Final directory
# $2 = NZB name
# $3 = Job name
# $4 = Report number
# $5 = Category
# $6 = Group
# $7 = Status (0 = success)
# $8 = Password (optional)

FINAL_DIR="$1"
NZB_NAME="$2"
JOB_NAME="$3"
REPORT_NUMBER="$4"
CATEGORY="$5"
GROUP="$6"
STATUS="$7"
PASSWORD="$8"

echo "[INFO] === ISO Post-Processing Script Started ==="
echo "[INFO] Final directory : $FINAL_DIR"
echo "[INFO] NZB name        : $NZB_NAME"
echo "[INFO] Job name        : $JOB_NAME"
echo "[INFO] Category        : $CATEGORY"
echo "[INFO] Group           : $GROUP"
echo "[INFO] SAB status      : $STATUS"

# Work only on successful jobs
if [ "$STATUS" != "0" ]; then
  echo "[WARN] SABnzbd status is not 0 (success). Skipping ISO extraction."
  echo "[INFO] === ISO Post-Processing Script Finished (no action) ==="
  exit 0
fi

# Check final directory
if [ -z "$FINAL_DIR" ] || [ ! -d "$FINAL_DIR" ]; then
  echo "[ERROR] Final directory is not set or does not exist: $FINAL_DIR"
  echo "[ERROR] Aborting ISO extraction."
  exit 1
fi

# Find extraction tool (7z preferred, fallback to bsdtar)
if command -v 7z >/dev/null 2>&1; then
  EXTRACT_CMD="7z x"
  echo "[INFO] Using extractor: 7z"
elif command -v bsdtar >/dev/null 2>&1; then
  EXTRACT_CMD="bsdtar -xf"
  echo "[INFO] Using extractor: bsdtar"
else
  echo "[ERROR] No extraction tool found (7z or bsdtar)."
  echo "[ERROR] Install p7zip/7z or bsdtar in the container image."
  exit 1
fi

ISO_FOUND=0

echo "[INFO] Searching for ISO files under: $FINAL_DIR"

# Search for ISO files (case-insensitive) in final directory and subdirectories
# Limit depth a bit to avoid traversing huge trees unnecessarily
while IFS= read -r -d '' iso_file; do
  ISO_FOUND=1
  echo "[INFO] Found ISO file: $iso_file"

  ISO_DIR="$(dirname "$iso_file")"
  echo "[INFO] Extracting into directory: $ISO_DIR"

  pushd "$ISO_DIR" >/dev/null 2>&1

  if $EXTRACT_CMD "$iso_file"; then
    echo "[INFO] Extraction successful for: $iso_file"
    echo "[INFO] Deleting ISO file: $iso_file"
    rm -f "$iso_file"
  else
    echo "[ERROR] Extraction failed for: $iso_file"
    popd >/dev/null 2>&1
    echo "[ERROR] Aborting ISO script with error."
    exit 1
  fi

  popd >/dev/null 2>&1
done < <(find "$FINAL_DIR" -maxdepth 5 -type f \( -iname "*.iso" \) -print0)

if [ "$ISO_FOUND" -eq 0 ]; then
  echo "[INFO] No ISO files found under: $FINAL_DIR"
fi

echo "[INFO] === ISO Post-Processing Script Finished Successfully ==="
exit 0
