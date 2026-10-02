#!/bin/sh

set -eu

ICON_DIR='/opt/local/MSP360 Backup/share/webAccess/img'
ICON_FILE="${ICON_DIR}/MainIcon.ico"

[ -d "${ICON_DIR}" ] || exit 0

# Restore the image defaults after the container has shut down.
chown root:root "${ICON_DIR}"
chmod 755 "${ICON_DIR}"

if [ -e "${ICON_FILE}" ]; then
    chown root:root "${ICON_FILE}"
    chmod 644 "${ICON_FILE}"
fi
