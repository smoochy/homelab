#!/bin/sh

set -eu

ICON_DIR='/opt/local/MSP360 Backup/share/webAccess/img'
ICON_FILE="${ICON_DIR}/MainIcon.ico"

[ -d "${ICON_DIR}" ] || exit 0

# Allow the MSP360 startup helper to replace the icon without failing.
chown app:app "${ICON_DIR}"

if [ -e "${ICON_FILE}" ]; then
    chown app:app "${ICON_FILE}"
fi
