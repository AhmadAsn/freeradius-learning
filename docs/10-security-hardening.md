# 10. Security Hardening

Production deployment checklist and security best practices for the FreeRADIUS Docker stack.

---

## Pre-Production Checklist

Complete every item before exposing this stack to production traffic.

### Secrets & Credentials

- [ ] **Change ALL passwords in `.env`** — generate with `openssl rand -base64 24`
  - `DB_ROOT_PASSWORD`
  - `DB_PASSWORD`
  - `RADIUS_CLIENTS_SECRET`
- [ ] **Change `breakglass` password** in `freeradius/config/users`
- [ ] **Change daloRADIUS admin password** (default: `administrator` / `radius`)
- [ ] **Use unique shared secrets per NAS device** in `clients.conf` (≥ 16 characters)
- [ ] **Store `.env` in a secrets manager** (HashiCorp Vault, AWS Secrets Manager, etc.) — never commit to git
- [ ] **Remove `.env.example` passwords** from any deployment artifacts

### Certificates

- [ ] **Replace self-signed certs** with PKI-signed certificates (see [TLS Certificates](09-tls-certificates.md))
- [ ] **Distribute `ca.pem`** to all supplicants via GPO/MDM
- [ ] **Set certificate expiry monitoring** (alert 30 days before expiration)

### Sample Data

- [ ] **Remove or change seed data** in `db/init/02-seed-data.sql`:
  - Delete `testuser`, `admin.test`, `guest01`, `contractor.a`
  - Or change all passwords to strong unique values
- [ ] **Remove wildcard client ranges** in `clients.conf` (only keep specific NAS IPs)

### Network

- [ ] **Firewall rules** — allow UDP 1812/1813 only from known NAS subnets
- [ ] **DB port bound to localhost** — verify `127.0.0.1:3307` (default)
- [ ] **Disable daloRADIUS** in production unless actively needed (`make mgmt-down`)
- [ ] **If using daloRADIUS** — restrict ports 80/8000 to admin workstations only

### FreeRADIUS Configuration

- [ ] **`require_message_authenticator = yes`** on all production NAS clients
- [ ] **`auth_badpass = no`** and **`auth_goodpass = no`** in `radiusd.conf` (default)
- [ ] **`reject_delay = 1`** or higher (slows brute force)
- [ ] **Review `max_attributes = 200`** — prevents attribute-stuffing attacks

### Docker Security

- [ ] **`no-new-privileges`** is enabled (default in compose)
- [ ] **Drop unnecessary capabilities** — the compose file should use `cap_drop: [ALL]` with explicit `cap_add`
- [ ] **Read-only filesystem** where possible
- [ ] **Resource limits** — verify `mem_limit` and `cpus` in docker-compose.yml
- [ ] **Non-root user** — FreeRADIUS runs as `freerad` user inside the container

### Operational

- [ ] **Schedule DB maintenance** — `make db-maintenance` weekly via cron
- [ ] **Schedule certificate rotation** — before expiry
- [ ] **Set up monitoring** — RADIUS port checks, Status-Server probes
- [ ] **Configure centralized logging** — ship radius.log to SIEM
- [ ] **Enable fail2ban** — see below
- [ ] **Rotate `breakglass` password** regularly

---

## Firewall Configuration

### iptables (Linux host)

```bash
# Allow RADIUS from known NAS subnets only
iptables -A INPUT -p udp --dport 1812 -s 10.0.1.0/24 -j ACCEPT  # Switches
iptables -A INPUT -p udp --dport 1813 -s 10.0.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 1812 -s 10.0.2.0/24 -j ACCEPT  # APs
iptables -A INPUT -p udp --dport 1813 -s 10.0.2.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 1812 -j DROP                      # Block all others
iptables -A INPUT -p udp --dport 1813 -j DROP

# Block external access to management ports
iptables -A INPUT -p tcp --dport 8000 -s 10.0.0.0/24 -j ACCEPT  # Admin workstations
iptables -A INPUT -p tcp --dport 8000 -j DROP
iptables -A INPUT -p tcp --dport 80 -j DROP
iptables -A INPUT -p tcp --dport 3307 -j DROP
```

### ufw (Ubuntu)

```bash
# Allow RADIUS from NAS subnets
ufw allow from 10.0.1.0/24 to any port 1812 proto udp
ufw allow from 10.0.1.0/24 to any port 1813 proto udp
ufw allow from 10.0.2.0/24 to any port 1812 proto udp
ufw allow from 10.0.2.0/24 to any port 1813 proto udp

# Block management ports from external
ufw deny 8000/tcp
ufw deny 3307/tcp
```

---

## fail2ban Integration

The stack includes a rate-limiting policy that logs failed auth attempts in a format parseable by fail2ban.

### Install fail2ban on the Docker host

```bash
apt-get install -y fail2ban
```

### Create the FreeRADIUS filter

```bash
cat > /etc/fail2ban/filter.d/freeradius.conf << 'EOF'
[Definition]
failregex = Login incorrect.*client\s+<HOST>
            Login incorrect:.*\(from client .* port .* cli <HOST>\)
ignoreregex =
EOF
```

### Create the jail

```bash
cat > /etc/fail2ban/jail.d/freeradius.conf << 'EOF'
[freeradius]
enabled  = true
port     = 1812,1813
protocol = udp
filter   = freeradius
# Point to the FreeRADIUS log file (via Docker volume or bind mount)
logpath  = /var/log/freeradius/radius.log
maxretry = 5
findtime = 300
bantime  = 3600
banaction = iptables-multiport[port="1812,1813", protocol="udp"]
EOF
```

### Activate

```bash
systemctl restart fail2ban
fail2ban-client status freeradius
```

### Expose the log for fail2ban

Add a volume mount to `docker-compose.yml`:

```yaml
freeradius:
  volumes:
    - ./freeradius/config:/etc/raddb-custom:ro
    - radius-logs:/var/log/freeradius        # Expose logs to host

volumes:
  radius-logs:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /var/log/freeradius
```

---

## Shared Secret Best Practices

| Guideline | Rationale |
|-----------|-----------|
| ≥ 16 characters | Prevents brute-force cracking of RADIUS packets |
| Unique per NAS device | Limits blast radius if one secret is compromised |
| No dictionary words | Resistant to dictionary attacks |
| Rotate annually | Limits exposure window |
| `require_message_authenticator = yes` | Prevents packet forgery attacks |

### Generate strong secrets

```bash
# 32-character random secret
openssl rand -base64 24

# Hex format (no special chars — safe for all NAS vendors)
openssl rand -hex 16
```

### clients.conf example (production)

```
# ❌ BAD: Wildcard subnet with weak secret
# client lan {
#     ipaddr = 10.0.0.0/8
#     secret = radius
# }

# ✅ GOOD: Per-device with strong secret
client core-sw01 {
    ipaddr    = 10.0.1.1
    secret    = a7f2e9c1b4d6083e5a9f7c2b1d4e6f8a
    nastype   = cisco
    shortname = core-sw01
    require_message_authenticator = yes
}

client wlc01 {
    ipaddr    = 10.0.2.1
    secret    = 3b8e7f1a2c5d9046e8b3a6f1c4d7e2b5
    nastype   = other
    shortname = wlc01
    require_message_authenticator = yes
}
```

---

## Logging for Security

### What to log

| Setting | Value | Why |
|---------|-------|-----|
| `auth = yes` | Log all auth events | Audit trail |
| `auth_badpass = no` | Don't log failed passwords | Prevents credential leaks in logs |
| `auth_goodpass = no` | Don't log successful passwords | Same |

### Centralized logging

For production, send logs to a SIEM (Splunk, ELK, Graylog):

**Option 1: Docker logging driver**

```yaml
# docker-compose.yml
freeradius:
  logging:
    driver: syslog
    options:
      syslog-address: "udp://siem.example.com:514"
      tag: "freeradius"
```

**Option 2: FreeRADIUS syslog destination**

In `radiusd.conf`:

```
log {
    destination = syslog
    syslog_facility = daemon
}
```

### Audit queries

```sql
-- Failed logins in the last hour
SELECT username, COUNT(*) AS attempts, MAX(authdate) AS latest
FROM radpostauth
WHERE reply = 'Access-Reject'
AND authdate > DATE_SUB(NOW(), INTERVAL 1 HOUR)
GROUP BY username
HAVING attempts >= 3
ORDER BY attempts DESC;

-- All auth events for a specific user
SELECT reply, authdate
FROM radpostauth
WHERE username = 'jdoe'
ORDER BY authdate DESC
LIMIT 50;
```

---

## Database Security

### Access control

- DB user (`radius`) should have minimal privileges:
  ```sql
  GRANT SELECT, INSERT, UPDATE, DELETE ON radius.* TO 'radius'@'%';
  ```
- DB port is bound to `127.0.0.1:3307` (not accessible from the network)
- Use a separate read-only user for reporting tools

### Encryption at rest

MariaDB 11 supports encryption at rest:

```ini
# In MariaDB config (my.cnf)
[mariadb]
innodb_encrypt_tables = ON
innodb_encrypt_log = ON
innodb_encryption_threads = 4
```

### Backup encryption

```bash
# Encrypted backup
docker exec mariadb mariadb-dump -u root -p"$DB_ROOT_PASSWORD" radius | \
    gpg --symmetric --cipher-algo AES256 -o backup.sql.gpg

# Restore
gpg -d backup.sql.gpg | docker exec -i mariadb mariadb -u root -p"$DB_ROOT_PASSWORD" radius
```

---

## Container Security

### Verify Docker security settings

```bash
# Check no-new-privileges
docker inspect freeradius --format '{{.HostConfig.SecurityOpt}}'
# Should include: no-new-privileges

# Check user
docker exec freeradius whoami
# Should be: freerad (not root)

# Check capabilities
docker inspect freeradius --format '{{.HostConfig.CapDrop}}'
```

### Network isolation

The stack uses a dedicated Docker bridge network (`radius-net`, 172.28.0.0/24). Only containers on this network can communicate with each other.

---

## Monitoring

### Health check (Status-Server)

The built-in health check sends a Status-Server request:

```bash
# Manual health check
docker exec freeradius radclient 127.0.0.1:1812 status testing123 <<< ""

# Via Makefile
make test-status
```

### External monitoring (Nagios/Zabbix/Prometheus)

```bash
# Simple check: can we authenticate?
echo "User-Name=testuser,User-Password=TestPass123!" | \
    radclient -t 3 radius-server:1812 auth "$SECRET"

# Check exit code: 0 = success, non-zero = failure
```

### Alert on

| Condition | Method |
|-----------|--------|
| FreeRADIUS not responding | Status-Server timeout |
| MariaDB connection lost | FreeRADIUS logs: "SQL connection failed" |
| Certificate expiring | `openssl x509 -checkend 2592000` (30 days) |
| High auth failure rate | Query `radpostauth` |
| Disk full (logs/accounting) | Standard disk monitoring |

---

## Next

- [Troubleshooting](11-troubleshooting.md) — Debug common issues
- [TLS Certificates](09-tls-certificates.md) — Certificate management
- [High Availability](12-high-availability.md) — Redundancy setup
