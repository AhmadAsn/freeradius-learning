#!/usr/bin/env bash
# =============================================================================
# FreeRADIUS Docker Entrypoint
# =============================================================================
set -euo pipefail

RADDB="/etc/freeradius"
CUSTOM="/etc/raddb-custom"
CERTDIR="${RADDB}/certs"

log() { echo "[entrypoint] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# =============================================================================
# 0. Validate required environment variables
# =============================================================================
MISSING=""
for var in DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD RADIUS_CLIENTS_SECRET; do
    eval val=\${${var}:-}
    if [ -z "$val" ]; then
        MISSING="${MISSING} ${var}"
    fi
done

if [ -n "$MISSING" ]; then
    log "ERROR: Required environment variables not set:${MISSING}"
    log "       Set them in .env or docker-compose.yml environment section."
    exit 1
fi

# =============================================================================
# 1. Copy custom config over the default raddb
# =============================================================================
log "Applying custom configuration..."

# Main configs
for f in radiusd.conf clients.conf users proxy.conf; do
    if [ -f "${CUSTOM}/${f}" ]; then
        cp "${CUSTOM}/${f}" "${RADDB}/${f}"
        log "  Copied ${f}"
    fi
done

# Module configs
if [ -d "${CUSTOM}/mods-available" ]; then
    count=$(find "${CUSTOM}/mods-available" -maxdepth 1 -type f | wc -l)
    if [ "$count" -gt 0 ]; then
        cp "${CUSTOM}"/mods-available/* "${RADDB}/mods-available/"
        log "  Copied ${count} module config(s)"
    fi
fi

# Site configs
if [ -d "${CUSTOM}/sites-available" ]; then
    count=$(find "${CUSTOM}/sites-available" -maxdepth 1 -type f | wc -l)
    if [ "$count" -gt 0 ]; then
        cp "${CUSTOM}"/sites-available/* "${RADDB}/sites-available/"
        log "  Copied ${count} site config(s)"
    fi
fi

# Policies
if [ -d "${CUSTOM}/policy.d" ]; then
    count=$(find "${CUSTOM}/policy.d" -maxdepth 1 -type f | wc -l)
    if [ "$count" -gt 0 ]; then
        cp "${CUSTOM}"/policy.d/* "${RADDB}/policy.d/"
        log "  Copied ${count} policy file(s)"
    fi
fi

# Fix known bug in default filter policy (wildcard deletion syntax)
sed -i 's/!\* ""/!* ANY/g' "${RADDB}/policy.d/filter" 2>/dev/null || true

# =============================================================================
# 2. Template environment variables into config files (envsubst)
# =============================================================================
log "Injecting environment variables..."

# Export defaults so envsubst can access them
export DB_HOST="${DB_HOST:-localhost}"
export DB_PORT="${DB_PORT:-3306}"
export DB_NAME="${DB_NAME:-radius}"
export DB_USER="${DB_USER:-radius}"
export DB_PASSWORD="${DB_PASSWORD:-radius}"
export RADIUS_CLIENTS_SECRET="${RADIUS_CLIENTS_SECRET:-testing123}"

# SQL module — inject DB credentials
# Uses explicit variable list so FreeRADIUS ${certdir} etc. are preserved
SQL_MOD="${RADDB}/mods-available/sql"
SQL_VARS='${DB_HOST} ${DB_PORT} ${DB_NAME} ${DB_USER} ${DB_PASSWORD}'
if [ -f "$SQL_MOD" ]; then
    envsubst "$SQL_VARS" < "$SQL_MOD" > "${SQL_MOD}.tmp"
    mv "${SQL_MOD}.tmp" "$SQL_MOD"
    log "  SQL module configured (${DB_HOST}:${DB_PORT}/${DB_NAME})"
fi

# clients.conf — inject shared secret
CLIENTS_CONF="${RADDB}/clients.conf"
CLIENT_VARS='${RADIUS_CLIENTS_SECRET}'
if [ -f "$CLIENTS_CONF" ]; then
    envsubst "$CLIENT_VARS" < "$CLIENTS_CONF" > "${CLIENTS_CONF}.tmp"
    mv "${CLIENTS_CONF}.tmp" "$CLIENTS_CONF"
    log "  Client secrets configured."
fi

# =============================================================================
# 3. Enable required modules (symlinks)
# =============================================================================
log "Enabling modules..."

cd "${RADDB}/mods-enabled"
for mod in always attr_filter cache_eap chap detail eap exec expiration \
           files linelog logintime mschap pap preprocess radutmp realm \
           sql soh suffix unpack utf8; do
    [ -f "../mods-available/${mod}" ] && ln -sf "../mods-available/${mod}" "${mod}" 2>/dev/null || true
done

# Enable sites
cd "${RADDB}/sites-enabled"
ln -sf "../sites-available/default" default 2>/dev/null || true
ln -sf "../sites-available/inner-tunnel" inner-tunnel 2>/dev/null || true

# =============================================================================
# 4. Generate self-signed certs if none exist
# =============================================================================
if [ ! -f "${CERTDIR}/server.pem" ] || [ ! -f "${CERTDIR}/dh" ] || [ ! -f "${CERTDIR}/ca.pem" ]; then
    log "TLS certificates missing or incomplete — generating self-signed certs..."
    /opt/radius-scripts/generate-certs.sh "${CERTDIR}"
else
    log "TLS certificates already present."
fi

# Ensure cert permissions
chown -R freerad:freerad "${CERTDIR}"
chmod 640 "${CERTDIR}"/*.key 2>/dev/null || true
chmod 644 "${CERTDIR}"/*.pem 2>/dev/null || true

# =============================================================================
# 5. Wait for database
# =============================================================================
log "Waiting for database at ${DB_HOST}:${DB_PORT}..."

MAX_RETRIES=30
RETRY=0
until mariadb -h "${DB_HOST}" -P "${DB_PORT}" \
              -u "${DB_USER}" -p"${DB_PASSWORD}" \
              -e "SELECT 1" "${DB_NAME}" &>/dev/null; do
    RETRY=$((RETRY + 1))
    if [ "$RETRY" -ge "$MAX_RETRIES" ]; then
        log "ERROR: Database not available after ${MAX_RETRIES} attempts. Exiting."
        exit 1
    fi
    log "  Attempt ${RETRY}/${MAX_RETRIES} — retrying in 2s..."
    sleep 2
done
log "Database is ready."

# =============================================================================
# 6. Fix ownership
# =============================================================================
chown -R freerad:freerad /var/log/freeradius
chown -R freerad:freerad "${RADDB}"

# =============================================================================
# 7. Validate configuration
# =============================================================================
log "Validating FreeRADIUS configuration..."
if ! freeradius -CX 2>&1 | tail -5; then
    log "ERROR: Configuration validation failed."
    freeradius -CX 2>&1 | grep -i "error" || true
    exit 1
fi
log "Configuration OK."

# =============================================================================
# 8. Start FreeRADIUS
# =============================================================================
if [ "${RADIUS_DEBUG:-false}" = "true" ]; then
    log "Starting FreeRADIUS in DEBUG mode (foreground)..."
    exec freeradius -X
else
    log "Starting FreeRADIUS in production mode (foreground)..."
    exec freeradius -f -l /var/log/freeradius/radius.log
fi
