# FreeRADIUS Docker Stack — Documentation

Complete tutorial and reference documentation for the FreeRADIUS Production Docker Stack.

---

## Contents

| # | Document | Description |
|---|----------|-------------|
| 1 | [Getting Started](01-getting-started.md) | Installation, first boot, verifying the stack works |
| 2 | [RADIUS Concepts](02-radius-concepts.md) | How RADIUS works — packets, attributes, auth flow, accounting |
| 3 | [Configuration Reference](03-configuration-reference.md) | Every config file explained, environment variables, templating |
| 4 | [Authentication Methods](04-authentication-methods.md) | PAP, CHAP, MS-CHAPv2, EAP-PEAP, EAP-TTLS, EAP-TLS |
| 5 | [802.1X Deployment](05-802.1x-deployment.md) | Wired/wireless 802.1X with VLAN assignment, supplicant setup |
| 6 | [Database & User Management](06-database-user-management.md) | Schema, SQL queries, groups, VLANs, accounting, Makefile commands |
| 7 | [daloRADIUS Administration](07-daloradius-guide.md) | Web UI setup, operators vs users portal, features walkthrough |
| 8 | [LDAP & Active Directory](08-ldap-active-directory.md) | AD integration, group mapping, LDAPS, troubleshooting |
| 9 | [TLS Certificates](09-tls-certificates.md) | Auto-generated certs, production PKI, rotation, client trust |
| 10 | [Security Hardening](10-security-hardening.md) | Production checklist, firewall, fail2ban, secrets management |
| 11 | [Troubleshooting](11-troubleshooting.md) | Common errors, debug mode, log analysis, diagnostic commands |
| 12 | [High Availability](12-high-availability.md) | Active/passive, active/active, Galera cluster, VIP failover |

---

## Quick Navigation

- **New to RADIUS?** Start with [RADIUS Concepts](02-radius-concepts.md), then [Getting Started](01-getting-started.md).
- **Setting up 802.1X?** Go to [Authentication Methods](04-authentication-methods.md) → [802.1X Deployment](05-802.1x-deployment.md).
- **Connecting Active Directory?** See [LDAP & Active Directory](08-ldap-active-directory.md).
- **Something broken?** Jump to [Troubleshooting](11-troubleshooting.md).
- **Going to production?** Review [Security Hardening](10-security-hardening.md) and [TLS Certificates](09-tls-certificates.md).
