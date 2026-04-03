#!/bin/bash
# =============================================================================
# db-maintenance.sh — Accounting & Post-Auth Log Cleanup
# =============================================================================
# Run via cron or manually:
#   docker exec radius-db /opt/db-scripts/db-maintenance.sh
#
# Defaults: keep 365 days of accounting, 90 days of post-auth logs.
# =============================================================================

set -euo pipefail

ACCT_RETENTION_DAYS="${ACCT_RETENTION_DAYS:-365}"
POSTAUTH_RETENTION_DAYS="${POSTAUTH_RETENTION_DAYS:-90}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${MYSQL_USER:-${DB_USER:-radius}}"
DB_PASS="${MYSQL_PASSWORD:-${DB_PASSWORD:-}}"
DB_NAME="${MYSQL_DATABASE:-${DB_NAME:-radius}}"

if [ -z "$DB_PASS" ]; then
    echo "ERROR: Database password not set. Set MYSQL_PASSWORD or DB_PASSWORD."
    exit 1
fi

MYSQL_CMD="mariadb -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASS} ${DB_NAME}"

echo "[$(date -Iseconds)] Starting RADIUS database maintenance..."

# --- Purge old accounting records ---
ACCT_COUNT=$(${MYSQL_CMD} -N -e \
    "SELECT COUNT(*) FROM radacct WHERE acctstarttime < DATE_SUB(NOW(), INTERVAL ${ACCT_RETENTION_DAYS} DAY);")
echo "  Accounting records older than ${ACCT_RETENTION_DAYS} days: ${ACCT_COUNT}"

if [ "${ACCT_COUNT}" -gt 0 ]; then
    ${MYSQL_CMD} --single-transaction -e \
        "DELETE FROM radacct WHERE acctstarttime < DATE_SUB(NOW(), INTERVAL ${ACCT_RETENTION_DAYS} DAY);"
    echo "  Deleted ${ACCT_COUNT} accounting records."
fi

# --- Purge old post-auth logs ---
POSTAUTH_COUNT=$(${MYSQL_CMD} -N -e \
    "SELECT COUNT(*) FROM radpostauth WHERE authdate < DATE_SUB(NOW(), INTERVAL ${POSTAUTH_RETENTION_DAYS} DAY);")
echo "  Post-auth records older than ${POSTAUTH_RETENTION_DAYS} days: ${POSTAUTH_COUNT}"

if [ "${POSTAUTH_COUNT}" -gt 0 ]; then
    ${MYSQL_CMD} --single-transaction -e \
        "DELETE FROM radpostauth WHERE authdate < DATE_SUB(NOW(), INTERVAL ${POSTAUTH_RETENTION_DAYS} DAY);"
    echo "  Deleted ${POSTAUTH_COUNT} post-auth records."
fi

# --- Optimize tables ---
echo "  Optimizing tables..."
${MYSQL_CMD} -e "OPTIMIZE TABLE radacct, radpostauth;" 2>/dev/null || true

echo "[$(date -Iseconds)] Maintenance complete."
