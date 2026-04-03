-- =============================================================================
-- 02-seed-data.sql — Sample Users, Groups, and VLAN Assignments
-- =============================================================================
-- ⚠️  DEVELOPMENT / TESTING DATA ONLY
-- Remove or replace ALL entries below before deploying to production.
--
-- For production:
--   1. Delete this file or replace contents with your real users
--   2. Use NT-Password hashes instead of Cleartext-Password for MSCHAPv2/PEAP
--   3. Use `make add-user` to add users after deployment
--
-- Generate NT-Password hash:
--   echo -n 'YourPassword' | iconv -t UTF-16LE | openssl dgst -md4 -provider legacy | awk '{print $NF}'
-- =============================================================================

USE radius;

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

-- Employees → VLAN 100
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
    ('employees',  'Tunnel-Type',              ':=', 'VLAN'),
    ('employees',  'Tunnel-Medium-Type',       ':=', 'IEEE-802'),
    ('employees',  'Tunnel-Private-Group-Id',  ':=', '100');

-- Guests → VLAN 200 with bandwidth limit
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
    ('guests',     'Tunnel-Type',              ':=', 'VLAN'),
    ('guests',     'Tunnel-Medium-Type',       ':=', 'IEEE-802'),
    ('guests',     'Tunnel-Private-Group-Id',  ':=', '200'),
    ('guests',     'WISPr-Bandwidth-Max-Down', ':=', '5000000'),
    ('guests',     'WISPr-Bandwidth-Max-Up',   ':=', '2000000');

-- Admins → VLAN 10 + Cisco priv 15
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
    ('admins',     'Tunnel-Type',              ':=', 'VLAN'),
    ('admins',     'Tunnel-Medium-Type',       ':=', 'IEEE-802'),
    ('admins',     'Tunnel-Private-Group-Id',  ':=', '10'),
    ('admins',     'Cisco-AVPair',             '+=', 'shell:priv-lvl=15');

-- Contractors → VLAN 150 with session timeout (8 hours)
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
    ('contractors', 'Tunnel-Type',              ':=', 'VLAN'),
    ('contractors', 'Tunnel-Medium-Type',       ':=', 'IEEE-802'),
    ('contractors', 'Tunnel-Private-Group-Id',  ':=', '150'),
    ('contractors', 'Session-Timeout',          ':=', '28800');

-- Group check: limit simultaneous sessions for guests
INSERT INTO radgroupcheck (groupname, attribute, op, value) VALUES
    ('guests',     'Simultaneous-Use',         ':=', '1');

-- ---------------------------------------------------------------------------
-- Sample Users
-- ---------------------------------------------------------------------------

-- Test employee (Cleartext for PAP testing; use NT-Password for MSCHAPv2)
INSERT INTO radcheck (username, attribute, op, value) VALUES
    ('testuser',   'Cleartext-Password',       ':=', 'TestPass123!');
INSERT INTO radusergroup (username, groupname, priority) VALUES
    ('testuser',   'employees', 1);

-- Test admin
INSERT INTO radcheck (username, attribute, op, value) VALUES
    ('admin.test', 'Cleartext-Password',       ':=', 'AdminPass456!');
INSERT INTO radusergroup (username, groupname, priority) VALUES
    ('admin.test', 'admins', 1);

-- Test guest
INSERT INTO radcheck (username, attribute, op, value) VALUES
    ('guest01',    'Cleartext-Password',       ':=', 'GuestPass789!');
INSERT INTO radusergroup (username, groupname, priority) VALUES
    ('guest01',    'guests', 1);

-- Test contractor
INSERT INTO radcheck (username, attribute, op, value) VALUES
    ('contractor.a', 'Cleartext-Password',     ':=', 'ContractorABC!');
INSERT INTO radusergroup (username, groupname, priority) VALUES
    ('contractor.a', 'contractors', 1);

-- ---------------------------------------------------------------------------
-- MAC Authentication Bypass (MAB) example
-- ---------------------------------------------------------------------------
-- Store MAC as both username and password (lowercase, no separators)
-- INSERT INTO radcheck (username, attribute, op, value) VALUES
--     ('aabbccddeeff', 'Cleartext-Password', ':=', 'aabbccddeeff');
-- INSERT INTO radusergroup (username, groupname, priority) VALUES
--     ('aabbccddeeff', 'guests', 1);
