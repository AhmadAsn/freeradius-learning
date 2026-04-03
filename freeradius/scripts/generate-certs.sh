#!/usr/bin/env bash
# =============================================================================
# generate-certs.sh — Self-signed CA + Server certificate for EAP
# =============================================================================
# Usage: generate-certs.sh <cert-directory>
#
# Generates:
#   ca.pem        — Self-signed Certificate Authority
#   ca.key        — CA private key
#   server.pem    — Server certificate (signed by CA)
#   server.key    — Server private key
#   dh            — Diffie-Hellman parameters (2048-bit)
#
# Environment variables (optional):
#   CERT_CA_CN        — CA Common Name        (default: FreeRADIUS CA)
#   CERT_SERVER_CN    — Server Common Name     (default: radius.local)
#   CERT_ORG          — Organization           (default: FreeRADIUS Docker)
#   CERT_COUNTRY      — Country code           (default: US)
#   CERT_STATE        — State / Province       (default: California)
#   CERT_CITY         — City / Locality        (default: San Francisco)
#   CERT_DAYS_CA      — CA validity in days    (default: 3650)
#   CERT_DAYS_SERVER  — Server cert validity   (default: 825)
#   DH_BITS           — DH parameter size      (default: 2048)
# =============================================================================
set -euo pipefail

CERTDIR="${1:?Usage: $0 <cert-directory>}"

# Defaults
CA_CN="${CERT_CA_CN:-FreeRADIUS CA}"
SERVER_CN="${CERT_SERVER_CN:-radius.local}"
ORG="${CERT_ORG:-FreeRADIUS Docker}"
COUNTRY="${CERT_COUNTRY:-US}"
STATE="${CERT_STATE:-California}"
CITY="${CERT_CITY:-San Francisco}"
DAYS_CA="${CERT_DAYS_CA:-3650}"
DAYS_SERVER="${CERT_DAYS_SERVER:-825}"
DH_BITS="${DH_BITS:-2048}"

log() { echo "[generate-certs] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

mkdir -p "${CERTDIR}"
cd "${CERTDIR}"

# =============================================================================
# 1. Generate CA key and self-signed certificate
# =============================================================================
log "Generating CA private key..."
openssl genrsa -out ca.key 4096

log "Generating self-signed CA certificate (${DAYS_CA} days)..."
openssl req -new -x509 -sha256 \
    -key ca.key \
    -out ca.pem \
    -days "${DAYS_CA}" \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/CN=${CA_CN}"

# =============================================================================
# 2. Generate server key and CSR
# =============================================================================
log "Generating server private key..."
openssl genrsa -out server.key 2048

log "Generating server certificate signing request..."
openssl req -new -sha256 \
    -key server.key \
    -out server.csr \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/CN=${SERVER_CN}"

# =============================================================================
# 3. Sign server certificate with CA (with SAN extension)
# =============================================================================
log "Signing server certificate with CA (${DAYS_SERVER} days)..."

cat > server-ext.cnf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVER_CN}
DNS.2 = localhost
DNS.3 = freeradius
IP.1  = 127.0.0.1
EOF

openssl x509 -req -sha256 \
    -in server.csr \
    -CA ca.pem \
    -CAkey ca.key \
    -CAcreateserial \
    -out server.pem \
    -days "${DAYS_SERVER}" \
    -extfile server-ext.cnf

# =============================================================================
# 4. Generate Diffie-Hellman parameters
# =============================================================================
log "Generating DH parameters (${DH_BITS}-bit) — this may take a moment..."
openssl dhparam -out dh "${DH_BITS}"

# =============================================================================
# 5. Cleanup temporary files
# =============================================================================
rm -f server.csr server-ext.cnf ca.srl

# =============================================================================
# 6. Set restrictive permissions
# =============================================================================
chmod 644 ca.pem server.pem dh
chmod 640 ca.key server.key

# =============================================================================
# 7. Verify
# =============================================================================
log "Verifying certificate chain..."
if openssl verify -CAfile ca.pem server.pem; then
    log "Certificate chain is valid."
else
    log "ERROR: Certificate verification failed!"
    exit 1
fi

log "Certificates generated successfully in ${CERTDIR}/"
log "  CA certificate:     ca.pem     (${DAYS_CA} days)"
log "  Server certificate: server.pem (${DAYS_SERVER} days)"
log "  Server key:         server.key"
log "  DH parameters:      dh         (${DH_BITS}-bit)"
log ""
log "WARNING: These are self-signed certificates for testing/development."
log "         For production, replace with PKI-signed certificates."
