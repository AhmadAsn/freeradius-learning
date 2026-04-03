# 11. Troubleshooting

Comprehensive troubleshooting guide for common issues with the FreeRADIUS Docker stack.

---

## Quick Diagnostic Commands

```bash
make status          # Container health
make logs            # All container logs
make logs-radius     # FreeRADIUS logs only
make logs-db         # MariaDB logs only
make debug           # Restart FreeRADIUS in verbose mode
make validate        # Check config syntax
make test            # Test PAP auth
make test-all        # Run all auth tests
make shell           # Shell into FreeRADIUS
make db-shell        # MariaDB CLI
```

---

## daloRADIUS Issues

### "Cannot Log In" to daloRADIUS

**Root cause (90% of cases):** You are on the wrong portal.

| Portal | URL | Default Credentials |
|--------|-----|-------------------|
| **Operators (Admin)** | `http://localhost:8000` | `administrator` / `radius` |
| **Users (Self-service)** | `http://localhost:80` | *(requires `userinfo` entry)* |

The admin login is on port **8000**. Port 80 is the **users portal** — it authenticates against the `userinfo` table, not the `operators` table.

**Fix:** Navigate to `http://localhost:8000` for admin access.

### daloRADIUS shows blank page

```bash
# Check PHP/Apache errors
docker logs daloradius --tail 50
docker exec daloradius cat /var/log/apache2/operators-error.log

# Verify PHP is installed
docker exec daloradius php -v

# Check Apache is listening on both ports
docker exec daloradius ss -tlnp | grep -E "80|8000"
```

### daloRADIUS database connection error

```bash
# Test DB connectivity from daloRADIUS container
docker exec daloradius mariadb -h db -u radius -p"$DB_PASSWORD" radius -e "SELECT 1;"

# Verify config was generated
docker exec daloradius cat /var/www/daloradius/app/common/includes/daloradius.conf.php | head -20

# Check if schema was imported
docker exec daloradius mariadb -h db -u radius -p"$DB_PASSWORD" radius -e "SHOW TABLES LIKE 'operators';"
```

### daloRADIUS container won't start

```bash
docker logs daloradius --tail 100

# Common causes:
# - DB not ready yet (daloRADIUS started before MariaDB)
# - Wrong DB credentials in .env
# - Port conflict (another service using 8000 or 80)
```

---

## FreeRADIUS Issues

### FreeRADIUS won't start

```bash
# Check exit code and error
docker logs freeradius --tail 50

# Validate config without starting
make validate

# Start in debug mode (shows every error in detail)
make debug
```

**Common causes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `Failed binding to auth address` | Port 1812 in use | Stop conflicting service or change `RADIUS_AUTH_PORT` |
| `Unknown module "sql"` | Module not enabled | Check entrypoint.sh symlink creation |
| `Could not read certificate file` | Missing/corrupt certs | `rm -f freeradius/config/certs/server.pem && make restart` |
| `Failed to connect to database` | MariaDB not ready | Wait for DB health check, or increase wait time in entrypoint |
| `Errors reading or parsing` | Syntax error in config | `make validate` – shows exact file and line |

### Container keeps restarting

```bash
# Check the last error before restart
docker logs freeradius --tail 50

# Check if health check is failing
docker inspect freeradius --format '{{json .State.Health}}'
```

---

## Authentication Issues

### "Login incorrect" (Access-Reject)

```bash
# Step 1: Check user exists in database
make db-shell
```

```sql
SELECT * FROM radcheck WHERE username = 'testuser';
-- Should see: Cleartext-Password  :=  TestPass123!
```

```bash
# Step 2: Check group assignment
```

```sql
SELECT * FROM radusergroup WHERE username = 'testuser';
-- Should see: groupname = employees
```

```bash
# Step 3: Test with radtest
docker exec freeradius radtest testuser TestPass123! 127.0.0.1 0 testing123
```

```bash
# Step 4: Check debug output
make debug
# Then test again and look for:
# - "Found Auth-Type = PAP" (credential found)
# - "Login incorrect" (wrong password)
# - "No Auth-Type found" (user not in DB)
```

**Common causes:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| "No Auth-Type found" | User not in `radcheck` | Insert user credentials |
| "Login incorrect" | Wrong password | Check `radcheck.value` matches |
| "Invalid user" | Wrong username format | Check canonicalization (case sensitivity) |
| "Module failed" | SQL connection lost | Check DB connectivity |

### EAP/802.1X authentication fails

```bash
# Debug mode shows TLS handshake details
make debug
```

**Check in the debug output:**

```
# Good - TLS handshake started:
eap_tls: TLS - Handshake is not finished

# Good - TLS tunnel established:
eap_tls: TLS - Session established

# Bad - certificate error:
TLS Alert: fatal:certificate_unknown
→ Client doesn't trust the CA. Distribute ca.pem.

# Bad - cipher mismatch:
TLS Alert: handshake_failure
→ Client and server share no ciphers. Check tls_min_version.

# Bad - inner auth failed:
Login incorrect (mschap: ...)
→ Wrong password or password format (need Cleartext-Password or NT-Password)
```

**Certificate issues:**

```bash
# Verify server cert is valid
docker exec freeradius openssl x509 -in /etc/raddb/certs/server.pem -noout -dates

# Verify cert chain
docker exec freeradius openssl verify -CAfile /etc/raddb/certs/ca.pem /etc/raddb/certs/server.pem

# Check if certs exist
docker exec freeradius ls -la /etc/raddb/certs/

# Force cert regeneration
rm -f freeradius/config/certs/server.pem
make restart
```

### "No matching client" / "Ignoring request"

FreeRADIUS received a RADIUS packet from an IP not in `clients.conf`:

```bash
# Check which IP is sending
make debug
# Look for: "Ignoring request to auth address * port 1812 from unknown client 10.0.1.99"

# Add the client
```

Edit `freeradius/config/clients.conf`:

```
client new-device {
    ipaddr    = 10.0.1.99
    secret    = UniqueSecret!
    nastype   = other
    shortname = new-device
    require_message_authenticator = yes
}
```

```bash
make restart
```

### Shared secret mismatch

Symptoms:
- NAS shows "RADIUS server not responding" even though FreeRADIUS is running
- FreeRADIUS debug shows garbled packets or no packets at all

```bash
# FreeRADIUS debug output when shared secret doesn't match:
# (no log entry at all — the packet is silently dropped)

# Or sometimes:
# "Received packet from X with invalid Message-Authenticator!"

# Fix: Ensure the secret in clients.conf matches the NAS exactly
# Watch for trailing spaces, special characters, or encoding issues
```

---

## Database Issues

### "Can't connect to MySQL server"

```bash
# Check MariaDB is running
docker ps | grep mariadb
make status

# Check MariaDB logs
make logs-db

# Test connectivity from FreeRADIUS container
docker exec freeradius mariadb -h db -u radius -p"$DB_PASSWORD" radius -e "SELECT 1;"

# Verify environment variables
docker exec freeradius env | grep DB_
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| MariaDB not started yet | Wait for health check or increase retry in entrypoint |
| Wrong `DB_HOST` | Should be `db` (Docker service name) |
| Wrong `DB_PASSWORD` | Check `.env` matches between services |
| MariaDB OOM killed | Increase `mem_limit` in docker-compose.yml |

### Schema missing (empty tables)

```bash
# Check if tables exist
make db-shell
```

```sql
SHOW TABLES;
-- Should see: radcheck, radreply, radusergroup, radgroupcheck,
-- radgroupreply, radacct, radpostauth, nas
```

If tables are missing:

```bash
# Re-import schema
docker exec -i mariadb mariadb -u root -p"$DB_ROOT_PASSWORD" radius < db/init/01-schema.sql

# Re-import seed data (optional)
docker exec -i mariadb mariadb -u root -p"$DB_ROOT_PASSWORD" radius < db/init/02-seed-data.sql
```

### Database full / slow queries

```sql
-- Check table sizes
SELECT
    table_name,
    ROUND(data_length / 1048576, 2) AS data_mb,
    table_rows
FROM information_schema.tables
WHERE table_schema = 'radius'
ORDER BY data_length DESC;

-- Usually radacct grows the fastest
-- Clean old records:
DELETE FROM radacct WHERE acctstarttime < DATE_SUB(NOW(), INTERVAL 180 DAY);
DELETE FROM radpostauth WHERE authdate < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- Or use the maintenance script:
-- make db-maintenance
```

---

## Certificate Issues

### "Could not read certificate file"

```bash
# Check files exist
docker exec freeradius ls -la /etc/raddb/certs/

# If missing, regenerate
rm -f freeradius/config/certs/server.pem
make restart
```

### Certificate expired

```bash
# Check expiry dates
docker exec freeradius openssl x509 -in /etc/raddb/certs/server.pem -noout -enddate
docker exec freeradius openssl x509 -in /etc/raddb/certs/ca.pem -noout -enddate

# Regenerate self-signed certs
rm -f freeradius/config/certs/server.pem
make restart

# Or replace with new production certs (see TLS Certificates guide)
```

### DH parameters error

```bash
# Regenerate
docker exec freeradius openssl dhparam -out /etc/raddb/certs/dh 2048

# Or from the host
openssl dhparam -out freeradius/config/certs/dh 2048
make restart
```

---

## Configuration Issues

### envsubst garbled config

Environment variable injection can fail if:

1. Password contains `$` and isn't escaped
2. `envsubst` isn't installed (missing `gettext-base`)
3. Explicit variable list is wrong

```bash
# Check if envsubst is available
docker exec freeradius which envsubst

# Inspect the generated config (after substitution)
docker exec freeradius cat /etc/raddb/mods-available/sql | head -20

# If passwords with $ are corrupted, escape in .env:
# DB_PASSWORD=my\$ecret
# Or use single quotes in docker-compose.yml environment section
```

### Module not found

```bash
# Check enabled modules
docker exec freeradius ls -la /etc/raddb/mods-enabled/

# Should see: sql, eap, mschap (at minimum)
# If missing, the entrypoint symlink creation failed

# Manual fix:
docker exec freeradius ln -sf /etc/raddb/mods-available/sql /etc/raddb/mods-enabled/sql
make restart
```

---

## Network Issues

### "Connection refused" from NAS

- FreeRADIUS might not be listening on the expected interface
- Docker port mapping might not be working

```bash
# Check FreeRADIUS is listening
docker exec freeradius ss -ulnp | grep 1812

# Check Docker port mapping
docker port freeradius

# Test from host
echo "User-Name=testuser,User-Password=TestPass123!" | \
    radclient localhost:1812 auth testing123
```

### Firewall blocking RADIUS traffic

```bash
# Check host firewall
iptables -L -n | grep 1812
ufw status | grep 1812

# Temporarily disable firewall for testing (put it back after!)
ufw disable     # UFW
iptables -F     # iptables (careful! — flushes all rules)
```

### Container can't resolve DNS

```bash
# Check DNS from inside the container
docker exec freeradius nslookup db
docker exec freeradius ping -c 2 db

# Check Docker network
docker network inspect radius-net
```

---

## Performance Issues

### High CPU usage

```bash
# Check what's using resources
docker stats

# Common cause: too many auth requests, underthreaded
# Fix: increase max_servers in radiusd.conf
# thread pool {
#     max_servers = 64
# }
```

### Slow authentication

```bash
# Enable debug temporarily to see timing
make debug

# Common causes:
# - DNS lookup timeout (if using hostnames in clients.conf)
# - LDAP server slow/unreachable
# - DB connection pool exhausted
```

```sql
-- Check DB connection count
SHOW PROCESSLIST;
```

---

## Collecting Diagnostic Information

When reporting an issue, gather this information:

```bash
# 1. Container status
make status

# 2. FreeRADIUS version
docker exec freeradius radiusd -v

# 3. Last 100 lines of logs
docker logs freeradius --tail 100 2>&1 > freeradius-logs.txt
docker logs mariadb --tail 100 2>&1 > mariadb-logs.txt

# 4. Config validation
make validate 2>&1 > config-check.txt

# 5. Environment (sanitize passwords!)
docker exec freeradius env | grep -v PASSWORD | grep -v SECRET > env-sanitized.txt

# 6. Certificate info
docker exec freeradius openssl x509 -in /etc/raddb/certs/server.pem -noout -subject -dates

# 7. Database state
docker exec mariadb mariadb -u radius -p"$DB_PASSWORD" radius -e "
    SELECT 'radcheck' AS t, COUNT(*) AS n FROM radcheck
    UNION ALL SELECT 'radreply', COUNT(*) FROM radreply
    UNION ALL SELECT 'radusergroup', COUNT(*) FROM radusergroup
    UNION ALL SELECT 'radacct', COUNT(*) FROM radacct
    UNION ALL SELECT 'radpostauth', COUNT(*) FROM radpostauth;"
```

---

## Next

- [High Availability](12-high-availability.md) — Redundancy and failover
- [Security Hardening](10-security-hardening.md) — Production checklist
- [Configuration Reference](03-configuration-reference.md) — All config files explained
