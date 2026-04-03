# 12. High Availability

Deployment patterns for redundant FreeRADIUS with failover and load distribution.

---

## Why HA for RADIUS?

If the RADIUS server goes down:
- **802.1X ports** stop authenticating new devices (existing sessions continue)
- **VPN logins** fail completely
- **Switch CLI** (TACACS+/RADIUS) access fails

Most NAS devices support **two RADIUS servers** (primary + secondary), making basic HA straightforward.

---

## Architecture Options

### Option 1: Active/Passive with VIP (Recommended)

```
┌──────────────────────────────────────┐
│          Keepalived VIP              │
│          10.0.0.100                  │
│             │                        │
│      ┌──────┴──────┐                 │
│      ▼              ▼                │
│ ┌─────────┐    ┌─────────┐          │
│ │ Host A  │    │ Host B  │          │
│ │ (MASTER)│    │(BACKUP) │          │
│ │         │    │         │          │
│ │ RADIUS  │    │ RADIUS  │          │
│ │ MariaDB │    │ MariaDB │          │
│ │ (primary│───▶│(replica)│          │
│ └─────────┘    └─────────┘          │
└──────────────────────────────────────┘
```

**How it works:**
1. Both hosts run the full stack
2. Keepalived manages a shared Virtual IP (VIP)
3. MariaDB primary-replica replication keeps data in sync
4. If Host A fails, keepalived moves the VIP to Host B
5. NAS devices always point at the VIP — no reconfiguration needed

**Pros:** Simple, well-tested pattern. NAS devices need only one IP.  
**Cons:** Standby host is idle. Failover takes 3–10 seconds.

### Option 2: Active/Active with Dual NAS Config

```
┌──────────────────────────────────────────┐
│                                          │
│  ┌─────────┐              ┌─────────┐   │
│  │ Host A  │              │ Host B  │   │
│  │ RADIUS  │              │ RADIUS  │   │
│  │         │              │         │   │
│  └────┬────┘              └────┬────┘   │
│       │                        │        │
│       └────────┬───────────────┘        │
│                ▼                         │
│         ┌──────────┐                     │
│         │ MariaDB  │                     │
│         │ Galera   │                     │
│         │ Cluster  │                     │
│         └──────────┘                     │
└──────────────────────────────────────────┘

NAS config:
  Primary RADIUS:   Host A (10.0.0.1)
  Secondary RADIUS: Host B (10.0.0.2)
```

**How it works:**
1. Both RADIUS servers are active and handle requests
2. NAS devices are configured with primary + secondary RADIUS
3. If primary fails, NAS automatically falls back to secondary
4. MariaDB Galera cluster provides multi-master replication

**Pros:** Both hosts handle traffic. No wasted resources.  
**Cons:** Requires all NAS devices to support dual RADIUS. More complex DB setup.

### Option 3: Active/Active with Load Balancer

```
┌────────────────────────────────────────┐
│                                        │
│         ┌──────────────┐               │
│         │ HAProxy/F5   │               │
│         │ UDP LB       │               │
│         │ :1812/:1813  │               │
│         └──────┬───────┘               │
│           ┌────┴────┐                  │
│           ▼         ▼                  │
│     ┌─────────┐ ┌─────────┐           │
│     │ RADIUS  │ │ RADIUS  │           │
│     │ Host A  │ │ Host B  │           │
│     └─────────┘ └─────────┘           │
│                                        │
└────────────────────────────────────────┘
```

**Pros:** True load balancing. Scalable to N nodes.  
**Cons:** UDP load balancing is tricky (no connection state). Adds complexity.

---

## Setting Up Active/Passive

### Step 1: Deploy the stack on both hosts

Clone the repo and configure `.env` identically on both hosts.

```bash
# Host A and Host B
git clone <repo-url> freeradius-docker
cd freeradius-docker
cp .env.example .env
# Edit .env with identical passwords and secrets
make build && make up
```

### Step 2: Configure MariaDB replication

On **Host A** (primary):

```sql
-- Create replication user
CREATE USER 'repl'@'%' IDENTIFIED BY 'ReplicationPassword!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

-- Get binary log position
SHOW MASTER STATUS;
-- Note the File and Position values
```

On **Host B** (replica):

```sql
CHANGE MASTER TO
    MASTER_HOST='host-a.example.com',
    MASTER_PORT=3307,
    MASTER_USER='repl',
    MASTER_PASSWORD='ReplicationPassword!',
    MASTER_LOG_FILE='mysql-bin.000001',    -- from SHOW MASTER STATUS
    MASTER_LOG_POS=154;                     -- from SHOW MASTER STATUS

START SLAVE;
SHOW SLAVE STATUS\G
-- Verify: Slave_IO_Running: Yes, Slave_SQL_Running: Yes
```

### Step 3: Install keepalived

On both hosts:

```bash
apt-get install -y keepalived
```

**Host A** (`/etc/keepalived/keepalived.conf`):

```
vrrp_script check_radius {
    script "/usr/bin/docker exec freeradius radclient -t 2 127.0.0.1:1812 status testing123 <<< '' >/dev/null 2>&1"
    interval 5
    weight -20
    fall 3
    rise 2
}

vrrp_instance RADIUS_VIP {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1

    virtual_ipaddress {
        10.0.0.100/24
    }

    track_script {
        check_radius
    }
}
```

**Host B** — same but `state BACKUP` and `priority 90`.

### Step 4: Configure NAS devices

Point all NAS devices at the VIP:

```
radius server FREERADIUS
    address ipv4 10.0.0.100 auth-port 1812 acct-port 1813
    key SharedSecret!
```

---

## Setting Up Active/Active

### NAS configuration

Most enterprise switches and APs support multiple RADIUS servers:

**Cisco IOS:**

```
radius server RADIUS-PRIMARY
    address ipv4 10.0.0.1 auth-port 1812 acct-port 1813
    key PrimarySecret!

radius server RADIUS-SECONDARY
    address ipv4 10.0.0.2 auth-port 1812 acct-port 1813
    key SecondarySecret!

aaa group server radius RADIUS-SERVERS
    server name RADIUS-PRIMARY
    server name RADIUS-SECONDARY
```

**Juniper:**

```
set access radius-server 10.0.0.1 secret "PrimarySecret!" port 1812
set access radius-server 10.0.0.2 secret "SecondarySecret!" port 1812
```

### Shared database (Galera Cluster)

For active/active, both RADIUS servers must share the same database. Use MariaDB Galera Cluster:

```yaml
# docker-compose.yml (simplified)
services:
  db:
    image: mariadb:11
    environment:
      MARIADB_GALERA_CLUSTER_NAME: radius_cluster
      MARIADB_GALERA_CLUSTER_ADDRESS: gcomm://host-a,host-b
    command: --wsrep-new-cluster  # Only on first node, first boot
```

Galera provides:
- Synchronous multi-master replication
- Automatic conflict resolution
- Node auto-join after failure

---

## Testing Failover

### Active/Passive test

```bash
# On Host A — stop FreeRADIUS
make down

# Verify VIP moved to Host B
ip addr show | grep 10.0.0.100   # Should appear on Host B

# Test authentication via VIP
radtest testuser TestPass123! 10.0.0.100 0 SharedSecret!
# Should succeed (routed to Host B)

# Restore Host A
make up
# VIP should move back to Host A (higher priority)
```

### Active/Active test

```bash
# Stop RADIUS on Host A
docker stop freeradius

# NAS should automatically fail over to Host B
# Check NAS logs for "RADIUS server 10.0.0.1 not responding, failing over"

# New auth requests should succeed via Host B
```

---

## Monitoring HA

### Check VRRP state

```bash
# On each host
systemctl status keepalived
journalctl -u keepalived --tail 20
```

### Check replication lag

```sql
-- On replica
SHOW SLAVE STATUS\G
-- Check: Seconds_Behind_Master (should be 0 or near 0)
```

### Health check script for monitoring tools

```bash
#!/bin/bash
# Check RADIUS is responding
timeout 3 radclient 127.0.0.1:1812 status testing123 <<< "" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "CRITICAL: FreeRADIUS not responding"
    exit 2
fi

# Check DB replication (on replica)
LAG=$(mysql -u root -p"$DB_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{print $2}')
if [ "$LAG" -gt 10 ]; then
    echo "WARNING: Replication lag ${LAG}s"
    exit 1
fi

echo "OK: RADIUS healthy, replication lag ${LAG:-0}s"
exit 0
```

---

## Next

- [Security Hardening](10-security-hardening.md) — Production checklist
- [Troubleshooting](11-troubleshooting.md) — Debug common issues
- [Getting Started](01-getting-started.md) — Back to basics
