# 1. Getting Started

This guide walks you through deploying the FreeRADIUS Docker stack from scratch, verifying it works, and running your first authentication test.

---

## Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Docker Engine | 20.10+ | 24.x+ |
| Docker Compose | v2.0+ | v2.20+ |
| RAM | 512 MB | 2 GB |
| Disk | 500 MB | 2 GB |
| OS | Linux, macOS, Windows (WSL2) | Linux |

### Install Docker (if not installed)

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Verify
docker --version
docker compose version
```

---

## Step 1: Clone and Configure

```bash
git clone <repo-url> freeradius-docker
cd freeradius-docker
```

### Create your environment file

```bash
cp .env.example .env
```

**Edit `.env`** and change every `CHANGE_ME` value. Generate strong passwords:

```bash
# Generate random passwords
openssl rand -base64 24    # → use for DB_ROOT_PASSWORD
openssl rand -base64 24    # → use for DB_PASSWORD
openssl rand -base64 24    # → use for RADIUS_CLIENTS_SECRET
```

Your `.env` should look like:

```env
# Database
DB_ROOT_PASSWORD=k7J3mN9xYp2qR4sT8vW1zA6bC5dE0fG
DB_NAME=radius
DB_USER=radius
DB_PASSWORD=hF2jK4lM6nP8qS0tU3vX5yA7bD9eG1iL
DB_EXTERNAL_PORT=3307

# RADIUS
RADIUS_AUTH_PORT=1812
RADIUS_ACCT_PORT=1813
RADIUS_CLIENTS_SECRET=wB4xC6yD8zA0eF2gH3iJ5kL7mN9oP1qR
RADIUS_DEBUG=false

# Timezone
TZ=UTC
```

> **Security:** Never commit `.env` to git. The `.gitignore` already excludes it.

---

## Step 2: Build and Start

```bash
# Build the FreeRADIUS image
make build

# Start the stack (FreeRADIUS + MariaDB)
make up
```

You should see:

```
[+] Running 3/3
 ✔ Network radius-net    Created
 ✔ Container mariadb     Started
 ✔ Container freeradius  Started
```

### Check container health

```bash
make status
```

Wait until both containers show `healthy`:

```
NAME         STATUS                  PORTS
mariadb      Up 30s (healthy)        127.0.0.1:3307->3306/tcp
freeradius   Up 25s (healthy)        0.0.0.0:1812->1812/udp, 0.0.0.0:1813->1813/udp
```

> **Note:** First boot takes 30–60 seconds while MariaDB initializes and FreeRADIUS generates TLS certificates.

---

## Step 3: Test Authentication

### Test with the sample user

The stack ships with sample users in `db/init/02-seed-data.sql`. Test with the default user:

```bash
make test
```

Expected output:

```
Sending Access-Request of id 123 to 127.0.0.1 port 1812
    User-Name = "testuser"
    User-Password = "TestPass123!"
Received Access-Accept of id 123 from 127.0.0.1:1812
```

### Run the full test suite

```bash
make test-all
```

This tests:
- `testuser` (employees group, VLAN 100)
- `admin.test` (admins group, VLAN 10)
- `guest01` (guests group, VLAN 200)
- Rejection of invalid credentials
- Status-Server probe (health check)

### Test manually with `radtest`

If you have `radtest` installed on the host:

```bash
radtest testuser TestPass123! localhost 0 testing123
```

Or from inside the container:

```bash
docker exec freeradius radtest testuser TestPass123! 127.0.0.1 0 testing123
```

---

## Step 4: Start the Management UI (Optional)

daloRADIUS provides a web interface for managing users, groups, and viewing accounting data:

```bash
make mgmt-up
```

Open your browser:

| Portal | URL | Credentials |
|--------|-----|-------------|
| **Admin (Operators)** | http://localhost:8000 | `administrator` / `radius` |
| **User Self-Service** | http://localhost:80 | *(requires userinfo account)* |

> **Important:** The admin portal is on port **8000**, not port 80!

To stop daloRADIUS:

```bash
make mgmt-down
```

---

## Step 5: View Logs

```bash
# All containers
make logs

# FreeRADIUS only
make logs-radius

# MariaDB only
make logs-db
```

Look for lines like:

```
Ready to process requests
```

This confirms FreeRADIUS started successfully.

---

## What's Next?

| Goal | Guide |
|------|-------|
| Understand how RADIUS works | [RADIUS Concepts](02-radius-concepts.md) |
| Add real users and groups | [Database & User Management](06-database-user-management.md) |
| Set up 802.1X on switches/APs | [802.1X Deployment](05-802.1x-deployment.md) |
| Connect Active Directory | [LDAP & Active Directory](08-ldap-active-directory.md) |
| Harden for production | [Security Hardening](10-security-hardening.md) |
| Use the web management UI | [daloRADIUS Administration](07-daloradius-guide.md) |

---

## Quick Reference: Makefile Commands

```bash
make build        # Build images
make up           # Start stack
make down         # Stop stack
make restart      # Restart FreeRADIUS
make status       # Container health
make logs         # Tail all logs
make test         # Test PAP auth
make test-all     # Full test suite
make shell        # Shell into FreeRADIUS container
make db-shell     # MariaDB CLI
make mgmt-up      # Start daloRADIUS
make mgmt-down    # Stop daloRADIUS
make clean        # Remove everything
```
