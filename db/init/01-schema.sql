-- =============================================================================
-- 01-schema.sql — FreeRADIUS MariaDB Schema
-- =============================================================================
-- Automatically executed on first container start via
-- /docker-entrypoint-initdb.d/
-- =============================================================================

USE radius;

-- ---------------------------------------------------------------------------
-- radcheck — per-user check attributes (credentials)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radcheck (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username    VARCHAR(64)  NOT NULL DEFAULT '',
    attribute   VARCHAR(64)  NOT NULL DEFAULT '',
    op          CHAR(2)      NOT NULL DEFAULT ':=',
    value       VARCHAR(253) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    INDEX idx_radcheck_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- radreply — per-user reply attributes (VLAN, bandwidth, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radreply (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username    VARCHAR(64)  NOT NULL DEFAULT '',
    attribute   VARCHAR(64)  NOT NULL DEFAULT '',
    op          CHAR(2)      NOT NULL DEFAULT '=',
    value       VARCHAR(253) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    INDEX idx_radreply_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- radgroupcheck — group check attributes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radgroupcheck (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    groupname   VARCHAR(64)  NOT NULL DEFAULT '',
    attribute   VARCHAR(64)  NOT NULL DEFAULT '',
    op          CHAR(2)      NOT NULL DEFAULT ':=',
    value       VARCHAR(253) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    INDEX idx_radgroupcheck_groupname (groupname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- radgroupreply — group reply attributes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radgroupreply (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    groupname   VARCHAR(64)  NOT NULL DEFAULT '',
    attribute   VARCHAR(64)  NOT NULL DEFAULT '',
    op          CHAR(2)      NOT NULL DEFAULT '=',
    value       VARCHAR(253) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    INDEX idx_radgroupreply_groupname (groupname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- radusergroup — user ↔ group mapping
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radusergroup (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username    VARCHAR(64)  NOT NULL DEFAULT '',
    groupname   VARCHAR(64)  NOT NULL DEFAULT '',
    priority    INT          NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    INDEX idx_radusergroup_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- radacct — accounting records
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radacct (
    radacctid           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    acctsessionid       VARCHAR(64)  NOT NULL DEFAULT '',
    acctuniqueid        VARCHAR(32)  NOT NULL DEFAULT '',
    username            VARCHAR(64)  NOT NULL DEFAULT '',
    realm               VARCHAR(64)  DEFAULT '',
    nasipaddress        VARCHAR(15)  NOT NULL DEFAULT '',
    nasportid           VARCHAR(50)  DEFAULT NULL,
    nasporttype         VARCHAR(32)  DEFAULT NULL,
    acctstarttime       DATETIME     DEFAULT NULL,
    acctupdatetime      DATETIME     DEFAULT NULL,
    acctstoptime        DATETIME     DEFAULT NULL,
    acctinterval        INT          DEFAULT NULL,
    acctsessiontime     INT UNSIGNED DEFAULT NULL,
    acctauthentic       VARCHAR(32)  DEFAULT NULL,
    connectinfo_start   VARCHAR(128) DEFAULT NULL,
    connectinfo_stop    VARCHAR(128) DEFAULT NULL,
    acctinputoctets     BIGINT       DEFAULT NULL,
    acctoutputoctets    BIGINT       DEFAULT NULL,
    calledstationid     VARCHAR(50)  NOT NULL DEFAULT '',
    callingstationid    VARCHAR(50)  NOT NULL DEFAULT '',
    acctterminatecause  VARCHAR(32)  NOT NULL DEFAULT '',
    servicetype         VARCHAR(32)  DEFAULT NULL,
    framedprotocol      VARCHAR(32)  DEFAULT NULL,
    framedipaddress     VARCHAR(15)  NOT NULL DEFAULT '',
    framedipv6address   VARCHAR(45)  NOT NULL DEFAULT '',
    framedipv6prefix    VARCHAR(45)  NOT NULL DEFAULT '',
    framedinterfaceid   VARCHAR(44)  NOT NULL DEFAULT '',
    delegatedipv6prefix VARCHAR(45)  NOT NULL DEFAULT '',
    class               VARCHAR(64)  DEFAULT NULL,
    PRIMARY KEY (radacctid),
    UNIQUE INDEX idx_acctuniqueid (acctuniqueid),
    INDEX idx_radacct_username (username),
    INDEX idx_radacct_nasip (nasipaddress),
    INDEX idx_radacct_starttime (acctstarttime),
    INDEX idx_radacct_stoptime (acctstoptime),
    INDEX idx_radacct_callingstation (callingstationid),
    INDEX idx_radacct_session (acctsessionid, nasipaddress, nasportid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- radpostauth — post-authentication log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS radpostauth (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    username    VARCHAR(64)  NOT NULL DEFAULT '',
    pass        VARCHAR(64)  NOT NULL DEFAULT '',
    reply       VARCHAR(32)  NOT NULL DEFAULT '',
    authdate    TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    class       VARCHAR(64)  DEFAULT NULL,
    PRIMARY KEY (id),
    INDEX idx_radpostauth_username (username),
    INDEX idx_radpostauth_authdate (authdate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- nas — NAS clients (for read_clients = yes in SQL module)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nas (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nasname     VARCHAR(128) NOT NULL,
    shortname   VARCHAR(32),
    type        VARCHAR(30)  DEFAULT 'other',
    ports       INT,
    secret      VARCHAR(60)  NOT NULL DEFAULT 'secret',
    server      VARCHAR(64),
    community   VARCHAR(50),
    description VARCHAR(200) DEFAULT 'RADIUS Client',
    PRIMARY KEY (id),
    INDEX idx_nas_nasname (nasname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
