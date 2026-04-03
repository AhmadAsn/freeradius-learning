#!/bin/bash
set -euo pipefail

DALO_PATH="/var/www/daloradius"

# ---------------------------------------------------------------------------
# 1. Create config from sample if it doesn't exist, then inject DB settings
# ---------------------------------------------------------------------------
CONFIG_FILE="${DALO_PATH}/app/common/includes/daloradius.conf.php"
SAMPLE_FILE="${CONFIG_FILE}.sample"

if [ ! -f "${CONFIG_FILE}" ] && [ -f "${SAMPLE_FILE}" ]; then
    cp "${SAMPLE_FILE}" "${CONFIG_FILE}"
    echo "[daloradius] Created config from sample."
fi

if [ -f "${CONFIG_FILE}" ]; then
    sed -i "s/\$configValues\['CONFIG_DB_ENGINE'\] = .*/\$configValues['CONFIG_DB_ENGINE'] = 'mysqli';/" "$CONFIG_FILE"
    sed -i "s/\$configValues\['CONFIG_DB_HOST'\] = .*/\$configValues['CONFIG_DB_HOST'] = '${MYSQL_HOST:-localhost}';/" "$CONFIG_FILE"
    sed -i "s/\$configValues\['CONFIG_DB_PORT'\] = .*/\$configValues['CONFIG_DB_PORT'] = '${MYSQL_PORT:-3306}';/" "$CONFIG_FILE"
    sed -i "s/\$configValues\['CONFIG_DB_USER'\] = .*/\$configValues['CONFIG_DB_USER'] = '${MYSQL_USER:-radius}';/" "$CONFIG_FILE"
    sed -i "s/\$configValues\['CONFIG_DB_PASS'\] = .*/\$configValues['CONFIG_DB_PASS'] = '${MYSQL_PASSWORD:-radius}';/" "$CONFIG_FILE"
    sed -i "s/\$configValues\['CONFIG_DB_NAME'\] = .*/\$configValues['CONFIG_DB_NAME'] = '${MYSQL_DATABASE:-radius}';/" "$CONFIG_FILE"
    sed -i "s|\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSSERVER'\] = .*|\$configValues['CONFIG_MAINT_TEST_USER_RADIUSSERVER'] = '${DEFAULT_FREERADIUS_SERVER:-127.0.0.1}';|" "$CONFIG_FILE"
    sed -i "s/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSSECRET'\] = .*/\$configValues['CONFIG_MAINT_TEST_USER_RADIUSSECRET'] = '${DEFAULT_CLIENT_SECRET:-testing123}';/" "$CONFIG_FILE"
    echo "[daloradius] Database configuration applied."
fi

# ---------------------------------------------------------------------------
# 2. Import daloRADIUS schema if not already done
# ---------------------------------------------------------------------------
SCHEMA_FILE="${DALO_PATH}/contrib/db/mariadb-daloradius.sql"
if [ -f "$SCHEMA_FILE" ]; then
    # Check if daloradius tables exist
    TABLE_COUNT=$(mariadb -h "${MYSQL_HOST:-localhost}" -P "${MYSQL_PORT:-3306}" \
        -u "${MYSQL_USER:-radius}" -p"${MYSQL_PASSWORD:-radius}" \
        "${MYSQL_DATABASE:-radius}" \
        -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE:-radius}' AND table_name='operators';" 2>/dev/null || echo "0")

    if [ "$TABLE_COUNT" = "0" ]; then
        echo "[daloradius] Importing daloRADIUS schema..."
        mariadb -h "${MYSQL_HOST:-localhost}" -P "${MYSQL_PORT:-3306}" \
            -u "${MYSQL_USER:-radius}" -p"${MYSQL_PASSWORD:-radius}" \
            "${MYSQL_DATABASE:-radius}" < "$SCHEMA_FILE" 2>/dev/null || true
        echo "[daloradius] Schema imported."
    else
        echo "[daloradius] daloRADIUS schema already present."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Add port 8000 to Apache ports.conf
# ---------------------------------------------------------------------------
if ! grep -q "Listen 8000" /etc/apache2/ports.conf; then
    echo "Listen 8000" >> /etc/apache2/ports.conf
fi

# ---------------------------------------------------------------------------
# 4. Fix permissions
# ---------------------------------------------------------------------------
chown -R www-data:www-data "${DALO_PATH}"

echo "[daloradius] Starting Apache..."
exec "$@"
