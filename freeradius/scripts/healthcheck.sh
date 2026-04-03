#!/usr/bin/env bash
# =============================================================================
# healthcheck.sh — FreeRADIUS container health check
# =============================================================================
# Sends a Status-Server request to verify FreeRADIUS is responsive.
# Used by Docker HEALTHCHECK directive.
# =============================================================================
set -euo pipefail

echo "Message-Authenticator = 0x00" | \
    radclient -c 1 -r 1 -t 3 127.0.0.1:1812 status testing123 > /dev/null 2>&1

exit $?
