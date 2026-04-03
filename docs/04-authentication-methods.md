# 4. Authentication Methods

This guide explains every authentication method supported by this stack, when to use each one, and how to configure and test them.

---

## Overview

| Method | Protocol | Use Case | Requires TLS | Default |
|--------|----------|----------|:------------:|:-------:|
| PAP | Password in cleartext (encrypted by shared secret) | Simple testing, legacy | No | Enabled |
| CHAP | Challenge-handshake | Legacy NAS devices | No | Enabled |
| MS-CHAPv2 | Microsoft challenge-handshake | VPN, inner EAP | No | Enabled |
| EAP-PEAP | TLS tunnel + MSCHAPv2 inside | **802.1X (most common)** | Yes | Enabled |
| EAP-TTLS | TLS tunnel + PAP/MSCHAP inside | 802.1X (cross-platform) | Yes | Enabled |
| EAP-TLS | Mutual TLS certificates | 802.1X (no passwords) | Yes | Enabled |

---

## PAP (Password Authentication Protocol)

### How it works

1. Client sends `User-Password` encrypted with the shared secret
2. RADIUS decrypts it and compares to the stored password
3. Stored password can be: `Cleartext-Password`, `MD5-Password`, `SHA1-Password`, `Crypt-Password`

### When to use

- Simple testing (`radtest`)
- Legacy devices that only support PAP
- Inner authentication inside EAP-TTLS

### Configuration

PAP is enabled by default. The `pap` module in `authorize` sets `Auth-Type = PAP` when it finds a compatible password attribute.

### Testing

```bash
# Using Makefile
make test

# Manual (from host)
radtest testuser TestPass123! localhost 0 testing123

# From inside the container
docker exec freeradius radtest testuser TestPass123! 127.0.0.1 0 testing123
```

### Password storage formats

In the `radcheck` table, the `attribute` column determines how the password is stored:

| Attribute | Format | Example |
|-----------|--------|---------|
| `Cleartext-Password` | Plain text | `TestPass123!` |
| `MD5-Password` | MD5 hash | `5f4dcc3b5aa765d61d8327deb882cf99` |
| `SHA1-Password` | SHA1 hash | `5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8` |
| `Crypt-Password` | Unix crypt | `$6$rounds=...` |
| `NT-Password` | NTLM hash (for MSCHAP) | `a4f49c406510bdcab6824ee7c30fd852` |

> **Recommendation:** Use `Cleartext-Password` so all auth methods work (PAP, CHAP, MSCHAP). If you only need PAP, you can use hashed passwords.

---

## CHAP (Challenge-Handshake Authentication Protocol)

### How it works

1. RADIUS sends a random challenge to the NAS
2. Client hashes the challenge with the password and sends the hash
3. RADIUS looks up the cleartext password, computes the same hash, and compares

### When to use

- Legacy NAS devices that don't support EAP
- Slightly more secure than PAP (password not sent in cleartext)

### Requirements

- Password **must** be stored as `Cleartext-Password` in `radcheck` (CHAP needs the original password to compute the hash)

### Testing

```bash
# CHAP requires radclient (radtest only does PAP)
echo "User-Name=testuser,CHAP-Password=TestPass123!" | \
    docker exec -i freeradius radclient 127.0.0.1 auth testing123
```

---

## MS-CHAPv2 (Microsoft Challenge-Handshake v2)

### How it works

1. RADIUS sends an NT challenge
2. Client computes an NT hash of the password and responds
3. RADIUS verifies using the NT hash (from DB) or `ntlm_auth` (AD)

### When to use

- VPN authentication (most VPN concentrators use MSCHAP)
- Inner auth method inside EAP-PEAP (the default)
- When connecting to Windows AD via `ntlm_auth`

### Requirements

- Password stored as `Cleartext-Password` or `NT-Password` in `radcheck`
- For MPPE encryption (VPN), `use_mppe = yes` in `mods-available/mschap`

### Configuration

Current settings in `mods-available/mschap`:

```
mschap {
    use_mppe           = yes     # Generate MPPE keys for encryption
    require_encryption = yes     # Require 128-bit MPPE
    require_strong     = yes     # Reject 40-bit MPPE
    with_ntdomain_hack = yes     # Strip DOMAIN\ from DOMAIN\username
}
```

### NT-Password generation

If you prefer hashed passwords, generate an NT hash:

```bash
# Using Python
python3 -c "import hashlib; print(hashlib.new('md4', 'TestPass123!'.encode('utf-16-le')).hexdigest())"

# Using samba-common-tools
echo -n "TestPass123!" | iconv -t utf-16le | openssl dgst -md4
```

Then store in `radcheck`:

```sql
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('jdoe', 'NT-Password', ':=', '<hash>');
```

---

## EAP-PEAP (Protected EAP)

### How it works (two phases)

```
Phase 1 (Outer): TLS Handshake
┌──────────┐                        ┌──────────────┐
│ Client   │◀── TLS Certificate ───│  FreeRADIUS   │
│          │─── Verify CA ─────────▶│              │
│          │◀══ TLS Tunnel ════════▶│              │
└──────────┘                        └──────────────┘

Phase 2 (Inner): MSCHAPv2 inside the tunnel
┌──────────┐                        ┌──────────────┐
│ Client   │── Username + MSCHAP ──▶│ inner-tunnel  │
│          │◀── Accept/Reject ──────│   server      │
└──────────┘                        └──────────────┘
```

1. **Phase 1:** Client and server establish a TLS tunnel. Client verifies the server's certificate against a trusted CA.
2. **Phase 2:** Inside the encrypted tunnel, the client authenticates with MSCHAPv2 (username + password).

### When to use

- **802.1X wired/wireless** — this is the most widely deployed method
- Windows has native PEAP support (no extra software needed)
- macOS, iOS, Android all support PEAP

### Configuration

In `mods-available/eap`:

```
eap {
    default_eap_type = peap

    peap {
        tls = tls-common              # Use the shared TLS config
        default_eap_type = mschapv2   # Inner auth = MSCHAPv2
        virtual_server = inner-tunnel  # Process inner auth here
        copy_request_to_tunnel = yes
        use_tunneled_reply = yes
    }
}
```

### Client setup (Windows 10/11)

1. Open **Settings → Network & Internet → Ethernet → Authentication**
2. Enable **IEEE 802.1X authentication**
3. Choose **Microsoft: Protected EAP (PEAP)**
4. Click **Settings**:
   - Validate server certificate: **Yes**
   - Trusted Root CAs: Select your CA (import `ca.pem`)
   - Authentication method: **EAP-MSCHAPv2**
   - Automatically use Windows logon: Optional (SSO)

### Testing PEAP

```bash
# Using eapol_test (from wpa_supplicant)
cat > /tmp/peap-test.conf << 'EOF'
network={
    ssid="test"
    key_mgmt=WPA-EAP
    eap=PEAP
    identity="testuser"
    password="TestPass123!"
    phase2="auth=MSCHAPV2"
    ca_cert="/path/to/ca.pem"
}
EOF

eapol_test -c /tmp/peap-test.conf -a 127.0.0.1 -s testing123
```

> **Note:** `eapol_test` is part of the `wpa_supplicant` package. On Debian/Ubuntu: `apt install eapoltest` or build from source.

---

## EAP-TTLS (Tunneled TLS)

### How it works

Similar to PEAP but more flexible:

1. **Phase 1:** TLS tunnel (same as PEAP)
2. **Phase 2:** Inner auth can be PAP, CHAP, MSCHAPv2, or even another EAP method

### When to use

- Cross-platform environments (Linux, macOS, Android prefer TTLS)
- When you need PAP as inner auth (e.g., for LDAP bind authentication)
- When PEAP isn't supported by the supplicant

### Configuration

In `mods-available/eap`:

```
eap {
    ttls {
        tls = tls-common
        default_eap_type = md5
        virtual_server = inner-tunnel
        copy_request_to_tunnel = yes
        use_tunneled_reply = yes
    }
}
```

### Key difference from PEAP

| | EAP-PEAP | EAP-TTLS |
|-|----------|----------|
| Inner auth | MSCHAPv2 (typically) | PAP, CHAP, MSCHAP, or EAP |
| Windows native | Yes | Requires third-party supplicant |
| Linux/macOS | Yes | Yes (preferred on Linux) |
| Password storage | Cleartext or NT-Password | Can use any format (if inner=PAP) |

### Testing TTLS

```bash
cat > /tmp/ttls-test.conf << 'EOF'
network={
    ssid="test"
    key_mgmt=WPA-EAP
    eap=TTLS
    identity="testuser"
    password="TestPass123!"
    phase2="auth=PAP"
    ca_cert="/path/to/ca.pem"
}
EOF

eapol_test -c /tmp/ttls-test.conf -a 127.0.0.1 -s testing123
```

---

## EAP-TLS (Certificate-based)

### How it works

Both client and server present TLS certificates. No passwords involved.

```
┌──────────┐                        ┌──────────────┐
│ Client   │── Client Certificate ─▶│  FreeRADIUS   │
│          │◀── Server Certificate ─│              │
│          │── Mutual TLS Auth ────▶│              │
│          │◀── Access-Accept ──────│              │
└──────────┘                        └──────────────┘
```

### When to use

- Highest security — no passwords to steal or guess
- Managed device environments (MDM can deploy certs)
- Corporate environments with existing PKI

### Requirements

- Each client device needs a unique certificate signed by your CA
- The CA that signed client certs must be trusted by FreeRADIUS
- Certificate lifecycle management (issuance, renewal, revocation)

### Configuration

In `mods-available/eap`:

```
eap {
    tls {
        tls = tls-common
        # The same tls-common config used by PEAP/TTLS
        # ca_file must include the CA that signed client certs
    }
}
```

### Generating client certificates

```bash
# Generate client key
openssl genrsa -out client.key 2048

# Generate CSR
openssl req -new -key client.key -out client.csr \
    -subj "/CN=jdoe/O=MyOrg/C=US"

# Sign with your CA
openssl x509 -req -in client.csr -CA ca.pem -CAkey ca.key \
    -CAcreateserial -out client.pem -days 365

# Create PKCS#12 for import into Windows/macOS
openssl pkcs12 -export -in client.pem -inkey client.key \
    -certfile ca.pem -out client.p12 -passout pass:changeme
```

Deploy `client.p12` to the device and `ca.pem` to FreeRADIUS.

---

## Method Selection Guide

### Choose based on your environment

```
Do you have a PKI / MDM?
├── Yes → EAP-TLS (no passwords, strongest security)
└── No
    ├── Mostly Windows clients?
    │   └── EAP-PEAP + MSCHAPv2 (native support, easy deployment)
    ├── Mixed OS (Linux, macOS, Android)?
    │   └── EAP-TTLS + PAP (universal support, flexible)
    ├── VPN authentication?
    │   └── MS-CHAPv2 (direct, no EAP wrapper)
    └── Simple testing / legacy?
        └── PAP (easiest, least secure)
```

### Password storage compatibility

| Auth Method | Cleartext-Password | NT-Password | MD5/SHA1 | Crypt |
|-------------|:------------------:|:-----------:|:--------:|:-----:|
| PAP | ✅ | ❌ | ✅ | ✅ |
| CHAP | ✅ | ❌ | ❌ | ❌ |
| MS-CHAPv2 | ✅ | ✅ | ❌ | ❌ |
| EAP-PEAP (MSCHAPv2) | ✅ | ✅ | ❌ | ❌ |
| EAP-TTLS (PAP) | ✅ | ❌ | ✅ | ✅ |
| EAP-TLS | N/A (certificate) | N/A | N/A | N/A |

> **Best practice:** Store passwords as `Cleartext-Password` to support all methods. If you only use one auth method, you can use the appropriate hash format.

---

## Next

- [802.1X Deployment](05-802.1x-deployment.md) — Deploy on real switches and APs
- [Database & User Management](06-database-user-management.md) — Add users to the database
- [TLS Certificates](09-tls-certificates.md) — Certificate management
