# 8. LDAP & Active Directory Integration

This guide covers connecting FreeRADIUS to LDAP or Microsoft Active Directory for user authentication, group mapping, and VLAN assignment.

---

## Overview

Instead of managing users in the MariaDB `radcheck` table, you can authenticate against Active Directory (AD) or any LDAP directory:

```
User ──▶ NAS ──▶ FreeRADIUS ──▶ Active Directory
                      │                  │
                      │         ┌────────┴────────┐
                      │         │ Bind as svc acct │
                      │         │ Search for user  │
                      │         │ Check group membership │
                      │         └────────┬────────┘
                      │                  │
                      │◀── User found ───┘
                      │
                      ▼
                   MariaDB
                 (group→VLAN mapping
                  + accounting only)
```

**What stays in SQL:** Group-to-VLAN mappings (`radgroupreply`), accounting (`radacct`), and post-auth logs  
**What moves to AD:** User authentication, group membership

---

## Prerequisites

1. A dedicated AD service account (e.g., `svc-radius`) with **read-only** access
2. The AD domain name and domain controller IP/hostname
3. Decide on LDAPS (port 636) vs STARTTLS (port 389) — LDAPS recommended
4. CA certificate for the domain controller (if using LDAPS with cert validation)

### Create the AD service account

In Active Directory Users and Computers:

1. Create OU: `Service Accounts`
2. Create user: `svc-radius`
3. Set password to never expire
4. Check: **Account options → Password never expires**
5. Uncheck: **User must change password at next logon**
6. Grant: **Read** permission on the user OU

### Get the DC certificate (for LDAPS)

```powershell
# On the domain controller (PowerShell)
Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.EnhancedKeyUsageList -like "*Server Authentication*"}

# Export the CA certificate
certutil -ca.cert ca-dc.pem
```

Copy `ca-dc.pem` to `freeradius/config/certs/ldap-ca.pem`.

---

## Step 1: Configure the LDAP Module

Edit `freeradius/config/mods-available/ldap`:

```
ldap {
    # ─── Connection ───────────────────────────────
    server   = 'ldaps://dc01.example.com'
    port     = 636

    # Service account credentials
    identity = 'CN=svc-radius,OU=Service Accounts,DC=example,DC=com'
    password = 'YourServiceAccountPassword!'

    # Base DN for all searches
    base_dn  = 'DC=example,DC=com'

    # ─── User Lookup ─────────────────────────────
    user {
        base_dn   = "${..base_dn}"
        # Match by sAMAccountName (AD username)
        filter    = "(sAMAccountName=%{%{Stripped-User-Name}:-%{User-Name}})"

        # Map AD attributes to RADIUS attributes
        scope     = 'sub'
    }

    # ─── Group Mapping ────────────────────────────
    group {
        base_dn       = "${..base_dn}"
        filter        = "(objectClass=group)"
        membership_attribute = "memberOf"
        name_attribute = "cn"

        # Support nested group membership
        membership_filter = "(|(member=%{control:Ldap-UserDn})(member=%{control:Ldap-UserDn}))"
    }

    # ─── TLS Configuration ───────────────────────
    tls {
        # Require valid certificate from the DC
        require_cert = "demand"

        # CA certificate that signed the DC's cert
        ca_file = "/etc/raddb/certs/ldap-ca.pem"
    }

    # ─── Connection Pool ─────────────────────────
    pool {
        start = 5
        min   = 4
        max   = 32
        idle_timeout  = 60
        retry_delay   = 30
    }
}
```

### For multiple domain controllers (HA)

```
server = 'ldaps://dc01.example.com ldaps://dc02.example.com'
```

### For STARTTLS instead of LDAPS

```
server = 'ldap://dc01.example.com'
port   = 389

tls {
    start_tls = yes
    require_cert = "demand"
    ca_file = "/etc/raddb/certs/ldap-ca.pem"
}
```

---

## Step 2: Enable the LDAP Module

Add to the FreeRADIUS Dockerfile or run inside the container:

```bash
# Create symlink to enable the module
ln -sf /etc/raddb/mods-available/ldap /etc/raddb/mods-enabled/ldap
```

Or add to `freeradius/Dockerfile`:

```dockerfile
RUN ln -sf /etc/raddb/mods-available/ldap /etc/raddb/mods-enabled/ldap
```

---

## Step 3: Update Virtual Server Configuration

Edit `freeradius/config/sites-available/default` to add LDAP to the processing pipeline:

### In the `authorize` section

Uncomment or add the `ldap` line:

```
authorize {
    filter_username
    filter_password
    preprocess
    suffix
    eap {
        ok = return
    }

    # Try SQL first, then LDAP
    sql
    -ldap               # The '-' means "don't fail if LDAP is down"

    files
    expiration
    logintime
    pap
    chap
    mschap
}
```

### In the `authenticate` section

Add LDAP authentication:

```
authenticate {
    Auth-Type PAP {
        pap
    }
    Auth-Type CHAP {
        chap
    }
    Auth-Type MS-CHAP {
        mschap
    }
    Auth-Type LDAP {
        ldap
    }
    eap
}
```

### Also update `sites-available/inner-tunnel`

Add the same `-ldap` line in the inner-tunnel's `authorize` section for EAP-PEAP/TTLS authentication.

---

## Step 4: Map AD Groups to VLANs

AD groups are matched based on the `memberOf` attribute. You have two approaches:

### Option A: Map in FreeRADIUS policy (recommended)

Create `freeradius/config/policy.d/ldap-group-mapping`:

```
policy ldap_group_vlan_mapping {
    # Admins (Domain Admins or Network Admins)
    if (&LDAP-Group[*] == "CN=Network Admins,OU=Groups,DC=example,DC=com") {
        update reply {
            &Tunnel-Type := VLAN
            &Tunnel-Medium-Type := IEEE-802
            &Tunnel-Private-Group-Id := "10"
        }
    }
    # Employees
    elsif (&LDAP-Group[*] == "CN=Employees,OU=Groups,DC=example,DC=com") {
        update reply {
            &Tunnel-Type := VLAN
            &Tunnel-Medium-Type := IEEE-802
            &Tunnel-Private-Group-Id := "100"
        }
    }
    # Contractors
    elsif (&LDAP-Group[*] == "CN=Contractors,OU=Groups,DC=example,DC=com") {
        update reply {
            &Tunnel-Type := VLAN
            &Tunnel-Medium-Type := IEEE-802
            &Tunnel-Private-Group-Id := "150"
            &Session-Timeout := 28800
        }
    }
    # Default — guests VLAN
    else {
        update reply {
            &Tunnel-Type := VLAN
            &Tunnel-Medium-Type := IEEE-802
            &Tunnel-Private-Group-Id := "200"
        }
    }
}
```

Add to `post-auth` in `sites-available/default`:

```
post-auth {
    ldap_group_vlan_mapping
    sql
}
```

### Option B: Map via SQL group names

Map AD group names to SQL group names in the `authorize` section. This lets you reuse your existing `radgroupreply` entries:

```
# In authorize section, after -ldap
if (&LDAP-Group[*] == "CN=Employees,OU=Groups,DC=example,DC=com") {
    update control {
        &User-Name := "%{User-Name}"
    }
    # This makes FreeRADIUS look up the 'employees' group in radgroupreply
    update request {
        &User-Name := "%{User-Name}"
    }
}
```

This approach requires inserting an `radusergroup` entry or using `unlang` to set the group dynamically.

---

## Step 5: MS-CHAPv2 with AD (ntlm_auth)

For EAP-PEAP with MSCHAPv2 against Active Directory, FreeRADIUS needs `ntlm_auth` (from Samba/Winbind):

### Why ntlm_auth?

MS-CHAPv2 requires the NT hash of the password. AD doesn't expose NT hashes via LDAP. Instead, `ntlm_auth` uses Winbind to perform NTLM authentication against AD natively.

### Setup

1. Install Samba/Winbind in the FreeRADIUS container (add to Dockerfile):

```dockerfile
RUN apt-get install -y samba winbind libnss-winbind libpam-winbind
```

2. Join the domain:

```bash
net ads join -U administrator
```

3. Configure `mods-available/mschap`:

```
mschap {
    use_mppe       = yes
    require_strong = yes

    ntlm_auth = "/usr/bin/ntlm_auth --request-nt-key \
        --username=%{%{Stripped-User-Name}:-%{User-Name}} \
        --domain=%{%{mschap:NT-Domain}:-EXAMPLE} \
        --challenge=%{%{mschap:Challenge}:-00} \
        --nt-response=%{%{mschap:NT-Response}:-00}"
}
```

### Alternative: EAP-TTLS + PAP

If setting up `ntlm_auth` is too complex, use **EAP-TTLS with PAP** as the inner method. PAP performs an LDAP bind to verify the password — no NT hash needed:

1. Set `default_eap_type = ttls` in `mods-available/eap`
2. Configure TTLS `default_eap_type = pap`
3. In `authorize`, LDAP sets `Auth-Type = LDAP`
4. In `authenticate`, `Auth-Type LDAP { ldap }` does an LDAP bind

This works with all client operating systems via EAP-TTLS.

---

## Step 6: Test and Rebuild

```bash
# Rebuild the image
make build

# Restart the stack
make up

# Test with an AD user
docker exec freeradius radtest jdoe 'ADPassword!' 127.0.0.1 0 testing123

# Debug mode (see LDAP queries in real-time)
make debug
```

### What to look for in debug output

```
# Successful LDAP lookup:
rlm_ldap: user jdoe found in directory
rlm_ldap: memberOf: CN=Employees,OU=Groups,DC=example,DC=com

# LDAP bind (password verification):
rlm_ldap: Bind as user DN: CN=John Doe,OU=Users,DC=example,DC=com
rlm_ldap: Bind successful

# Failed lookup:
rlm_ldap: user jdoe NOT found in directory
```

---

## Hybrid Setup (SQL + LDAP)

You can use both backends simultaneously:

- **LDAP** for domain users (employees, contractors)
- **SQL** for local accounts (service accounts, MAC auth, emergency access)

The `authorize` section processes modules in order:

```
authorize {
    ...
    sql        # Check SQL first
    -ldap      # Then check LDAP (- prefix = don't fail if LDAP is unreachable)
    ...
}
```

If a user is found in SQL, `Auth-Type` is set and LDAP is skipped. If not found in SQL, LDAP is checked.

---

## Troubleshooting LDAP

### Connection refused

```bash
# Test LDAP connectivity from the container
docker exec freeradius ldapsearch -H ldaps://dc01.example.com:636 \
    -D "CN=svc-radius,OU=Service Accounts,DC=example,DC=com" \
    -w "password" \
    -b "DC=example,DC=com" \
    "(sAMAccountName=testuser)" dn

# If ldapsearch isn't available:
docker exec freeradius apt-get install -y ldap-utils
```

### Certificate errors

```bash
# Test TLS connection
docker exec freeradius openssl s_client -connect dc01.example.com:636 \
    -CAfile /etc/raddb/certs/ldap-ca.pem

# Temporarily disable cert validation for testing (NOT for production)
# In ldap module: require_cert = "never"
```

### "User not found" but user exists in AD

1. Check the `filter` — is it matching the right attribute?
   - AD: `sAMAccountName` (pre-Windows 2000 name)
   - Modern: `userPrincipalName` (email-style)
2. Check `base_dn` — is it broad enough to include the user's OU?
3. Check realm stripping — if user logs in as `DOMAIN\jdoe`, the `with_ntdomain_hack` in mschap strips the domain

### LDAP too slow

- Increase `pool.min` and `pool.start`
- Add a secondary DC: `server = 'ldaps://dc01 ldaps://dc02'`
- Check network latency between the Docker host and DC
- Ensure the `filter` uses an indexed attribute (`sAMAccountName` is indexed by default)

---

## Next

- [TLS Certificates](09-tls-certificates.md) — Certificate management for EAP
- [Security Hardening](10-security-hardening.md) — Production checklist
- [Troubleshooting](11-troubleshooting.md) — General troubleshooting
