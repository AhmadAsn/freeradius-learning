# 9. TLS Certificates

This guide covers certificate management for EAP-based 802.1X authentication — auto-generated certs for testing, production PKI setup, and certificate rotation.

---

## Why TLS Matters for RADIUS

EAP methods (PEAP, TTLS, TLS) establish a TLS tunnel between the supplicant and FreeRADIUS. This requires:

1. **Server certificate** — proves the RADIUS server's identity to clients
2. **CA certificate** — the trust anchor; clients verify the server cert is signed by this CA
3. **DH parameters** — for Diffie-Hellman key exchange (forward secrecy)

```
Client (Supplicant)                       FreeRADIUS
─────────────────                         ──────────
     │                                        │
     │◀──── server.pem (server certificate) ──│
     │                                        │
     │── Verify against trusted CA ──────────▶│
     │   (ca.pem must be trusted)             │
     │                                        │
     │◀════ TLS Tunnel Established ══════════▶│
     │                                        │
     │── Username + Password (encrypted) ────▶│
```

---

## Auto-Generated Certificates (Default)

On first boot, `generate-certs.sh` creates a self-signed PKI:

### Generated files

| File | Description | Key Size | Validity |
|------|-------------|----------|----------|
| `ca.key` | CA private key | 4096-bit RSA | — |
| `ca.pem` | CA certificate | — | 3650 days (10 years) |
| `server.key` | Server private key | 2048-bit RSA | — |
| `server.pem` | Server certificate (signed by CA) | — | 825 days (~2.3 years) |
| `dh` | Diffie-Hellman parameters | 2048-bit | — |

### Location

```
freeradius/config/certs/
├── ca.key           # CA private key (keep secure!)
├── ca.pem           # CA certificate (distribute to clients)
├── server.key       # Server private key
├── server.pem       # Server certificate
└── dh               # DH parameters
```

### Certificate details

The generated certificates use these defaults (configurable via environment variables):

| Field | Default | Environment Variable |
|-------|---------|---------------------|
| CA Common Name | `FreeRADIUS CA` | `CERT_CA_CN` |
| Server Common Name | `radius.local` | `CERT_SERVER_CN` |
| Organization | `FreeRADIUS Docker` | `CERT_ORG` |
| Country | `US` | `CERT_COUNTRY` |
| State | `California` | `CERT_STATE` |
| City | `San Francisco` | `CERT_CITY` |
| CA validity | 3650 days | `CERT_DAYS_CA` |
| Server validity | 825 days | `CERT_DAYS_SERVER` |
| DH bits | 2048 | `DH_BITS` |

### Subject Alternative Names (SAN)

The server certificate includes these SANs:
- `localhost`
- `freeradius` (Docker service name)
- `127.0.0.1`

### Customizing auto-generated certs

Set variables in `.env` before first boot:

```env
CERT_CA_CN=MyCompany RADIUS CA
CERT_SERVER_CN=radius.mycompany.com
CERT_ORG=MyCompany Inc
CERT_COUNTRY=DE
CERT_STATE=Bavaria
CERT_CITY=Munich
CERT_DAYS_CA=7300
CERT_DAYS_SERVER=730
DH_BITS=4096
```

### Regenerating self-signed certs

```bash
# Remove existing certs (forces regeneration on next start)
rm -f freeradius/config/certs/server.pem

# Restart — entrypoint detects missing cert and runs generate-certs.sh
make restart
```

---

## Production Certificates

For production, replace self-signed certs with certificates from your organization's PKI or a public CA.

### Requirements

| Component | Requirement |
|-----------|------------|
| Server certificate | Signed by your internal CA (or public CA) |
| Key format | PEM (RSA 2048-bit or ECDSA P-256+) |
| Certificate chain | Include intermediate CAs in `ca.pem` |
| DH parameters | At least 2048-bit |

### Step 1: Generate a CSR from FreeRADIUS

```bash
# Generate a new private key
openssl genrsa -out freeradius/config/certs/server.key 2048

# Generate a CSR
openssl req -new \
    -key freeradius/config/certs/server.key \
    -out server.csr \
    -subj "/CN=radius.mycompany.com/O=MyCompany/C=US" \
    -addext "subjectAltName=DNS:radius.mycompany.com,DNS:radius,IP:10.0.0.10"
```

### Step 2: Submit CSR to your CA

Submit `server.csr` to your internal CA (Active Directory Certificate Services, HashiCorp Vault, etc.) and get back the signed certificate.

### Step 3: Install the certificates

```bash
# Server certificate (signed by CA)
cp /path/to/signed/server.pem freeradius/config/certs/server.pem

# CA certificate (+ intermediate chain)
cp /path/to/ca-chain.pem freeradius/config/certs/ca.pem

# Server private key
cp /path/to/server.key freeradius/config/certs/server.key

# DH parameters (if not already present)
openssl dhparam -out freeradius/config/certs/dh 2048
```

### Step 4: Set permissions

```bash
chmod 644 freeradius/config/certs/ca.pem
chmod 644 freeradius/config/certs/server.pem
chmod 640 freeradius/config/certs/server.key
chmod 644 freeradius/config/certs/dh
```

### Step 5: Verify the certificate chain

```bash
# Verify server cert is signed by CA
openssl verify -CAfile freeradius/config/certs/ca.pem \
    freeradius/config/certs/server.pem

# Check certificate details
openssl x509 -in freeradius/config/certs/server.pem -noout -text | \
    grep -E "Issuer|Subject|Not After|DNS"
```

### Step 6: Restart

```bash
make restart
```

---

## Certificate Rotation

### When to rotate

- Server certificate is approaching expiration
- CA certificate is being replaced
- Security incident (key compromise)

### Rotation procedure

```bash
# 1. Backup existing certs
cp -r freeradius/config/certs/ freeradius/config/certs.bak/

# 2. Replace certificate files
cp /path/to/new/ca.pem     freeradius/config/certs/ca.pem
cp /path/to/new/server.pem freeradius/config/certs/server.pem
cp /path/to/new/server.key freeradius/config/certs/server.key

# 3. Verify the new chain
openssl verify -CAfile freeradius/config/certs/ca.pem \
    freeradius/config/certs/server.pem

# 4. Restart FreeRADIUS
make restart

# 5. Test EAP authentication
make test

# 6. Remove backup (after confirming everything works)
rm -rf freeradius/config/certs.bak/
```

### CA rotation (breaking change)

If you're replacing the CA certificate, **all supplicants must trust the new CA**:

1. Deploy the new CA to all clients first (via GPO, MDM, or manual)
2. During transition, include both old and new CA in `ca.pem` (concatenate)
3. Replace the server cert (signed by new CA)
4. After all clients trust the new CA, remove the old CA

```bash
# Transition CA file (both CAs)
cat new-ca.pem old-ca.pem > freeradius/config/certs/ca.pem
```

---

## Client Certificate Trust

### Distribute `ca.pem` to clients

Every 802.1X supplicant must trust the RADIUS server's CA. Without this:
- **Windows:** "The server's certificate is not trusted" warning
- **macOS:** Connection refused
- **Android:** "CA certificate not installed" error
- **Linux:** `eapol_test` fails with TLS errors

### Distribution methods

| Method | Platform | Approach |
|--------|----------|----------|
| **Group Policy (GPO)** | Windows | Computer Config → Policies → Windows Settings → Security → Trusted Root CAs |
| **MDM Profile** | macOS/iOS | `.mobileconfig` profile with embedded CA cert |
| **MDM** | Android | Deploy via Android Enterprise managed configuration |
| **Manual** | Linux | Copy to `/usr/local/share/ca-certificates/` + `update-ca-certificates` |
| **wpa_supplicant** | Linux | Set `ca_cert="/path/to/ca.pem"` in config |

### Extract `ca.pem` from the running stack

```bash
# Copy from container
docker cp freeradius:/etc/raddb/certs/ca.pem ./ca.pem

# Or read from the host mount
cat freeradius/config/certs/ca.pem
```

---

## EAP-TLS Client Certificates

For certificate-based authentication (EAP-TLS), each client needs its own certificate.

### Generate a client certificate

```bash
# 1. Generate client private key
openssl genrsa -out client.key 2048

# 2. Generate CSR
openssl req -new -key client.key -out client.csr \
    -subj "/CN=jdoe/O=MyCompany/C=US"

# 3. Sign with the RADIUS CA
openssl x509 -req -in client.csr \
    -CA freeradius/config/certs/ca.pem \
    -CAkey freeradius/config/certs/ca.key \
    -CAcreateserial \
    -out client.pem \
    -days 365 \
    -extfile <(echo "basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth")

# 4. Create PKCS#12 for Windows/macOS import
openssl pkcs12 -export \
    -in client.pem \
    -inkey client.key \
    -certfile freeradius/config/certs/ca.pem \
    -out client.p12 \
    -passout pass:importpassword
```

### Deploy client certificate

- **Windows:** Import `client.p12` into the personal certificate store
- **macOS:** Import `client.p12` into Keychain Access
- **Linux:** Reference `client.pem` and `client.key` in `wpa_supplicant.conf`
- **Android:** Import via Settings → Security → Install from storage

---

## TLS Configuration in EAP Module

The TLS settings in `mods-available/eap` control the server-side TLS behavior:

```
tls-config tls-common {
    private_key_file = /etc/raddb/certs/server.key
    certificate_file = /etc/raddb/certs/server.pem
    ca_file          = /etc/raddb/certs/ca.pem
    dh_file          = /etc/raddb/certs/dh

    # TLS version range
    tls_min_version = "1.2"      # Minimum (1.2 recommended)
    tls_max_version = "1.3"      # Maximum

    # Cipher suites (TLS 1.2)
    cipher_list = "ECDHE+AESGCM:ECDHE+CHACHA20:..."

    # Session caching (performance optimization)
    cache {
        enable = yes
        lifetime = 24             # hours
        max_entries = 255         # cached sessions
    }
}
```

### Hardening TLS

| Setting | Recommendation | Why |
|---------|---------------|-----|
| `tls_min_version` | `"1.2"` | TLS 1.0/1.1 are deprecated |
| `tls_max_version` | `"1.3"` | Best available |
| `cipher_list` | ECDHE + AESGCM only | Forward secrecy + authenticated encryption |
| RSA key size | ≥ 2048-bit | Minimum for current security |
| ECDSA | P-256 or P-384 | Faster than RSA, equally secure |

---

## Troubleshooting Certificates

### "SSL alert: certificate unknown"

The supplicant doesn't trust the CA. Distribute `ca.pem` to the client.

### "SSL: SSL_read failed"

```bash
# Check cert is valid and not expired
openssl x509 -in freeradius/config/certs/server.pem -noout -dates

# Verify chain
openssl verify -CAfile freeradius/config/certs/ca.pem \
    freeradius/config/certs/server.pem
```

### "No matching cipher"

Client and server don't share compatible ciphers. Check `tls_min_version` — if clients only support TLS 1.0, you may need to lower it (not recommended).

### DH parameter errors

```bash
# Regenerate DH parameters
openssl dhparam -out freeradius/config/certs/dh 2048

# Verify
openssl dhparam -in freeradius/config/certs/dh -check
```

### Check all certs at once

```bash
# From inside the container
docker exec freeradius bash -c '
for f in /etc/raddb/certs/*.pem; do
    echo "=== $f ==="
    openssl x509 -in "$f" -noout -subject -issuer -dates 2>/dev/null
done'
```

---

## Next

- [Security Hardening](10-security-hardening.md) — Full production checklist
- [Authentication Methods](04-authentication-methods.md) — EAP method details
- [802.1X Deployment](05-802.1x-deployment.md) — Supplicant configuration
