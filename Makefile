# =============================================================================
# Makefile — FreeRADIUS Docker Stack Operations
# =============================================================================

.PHONY: help up down restart logs build test test-eap status shell db-shell \
        db-maintenance add-user list-users delete-user mgmt-up mgmt-down clean

COMPOSE = docker compose
RADIUS  = docker exec freeradius
DB      = docker exec radius-db

# Default shared secret (from .env)
SECRET ?= testing123

# DB credentials — sourced from .env automatically by make
# Override: make add-user USER=jdoe PASS=secret DB_PASS=mypass
DB_PASS ?= $(DB_PASSWORD)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

build: ## Build FreeRADIUS image
	$(COMPOSE) build

up: ## Start the stack (detached)
	$(COMPOSE) up -d

down: ## Stop the stack
	$(COMPOSE) down

restart: ## Restart FreeRADIUS (without DB restart)
	$(COMPOSE) restart freeradius

logs: ## Tail all logs
	$(COMPOSE) logs -f --tail=100

logs-radius: ## Tail FreeRADIUS logs only
	$(COMPOSE) logs -f --tail=100 freeradius

logs-db: ## Tail MariaDB logs only
	$(COMPOSE) logs -f --tail=100 db

status: ## Show container status and health
	$(COMPOSE) ps

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------

test: ## Test PAP authentication (testuser)
	$(RADIUS) radtest testuser TestPass123! 127.0.0.1 0 $(SECRET)

test-admin: ## Test admin authentication
	$(RADIUS) radtest admin.test AdminPass456! 127.0.0.1 0 $(SECRET)

test-guest: ## Test guest authentication
	$(RADIUS) radtest guest01 GuestPass789! 127.0.0.1 0 $(SECRET)

test-reject: ## Test that an invalid user is rejected
	$(RADIUS) radtest baduser wrongpassword 127.0.0.1 0 $(SECRET) || true

test-status: ## Send Status-Server request
	$(RADIUS) sh -c 'echo "Message-Authenticator = 0x00" | radclient 127.0.0.1:1812 status $(SECRET)'

test-all: test test-admin test-guest test-reject test-status ## Run all tests
	@echo "\n✅ All tests complete."

# ---------------------------------------------------------------------------
# User Management (SQL)
# ---------------------------------------------------------------------------

add-user: ## Add a user: make add-user USER=jdoe PASS=secret GROUP=employees
	@test -n "$(USER)" || (echo "ERROR: USER is required" && exit 1)
	@test -n "$(PASS)" || (echo "ERROR: PASS is required" && exit 1)
	@test -n "$(DB_PASS)" || (echo "ERROR: DB_PASS or DB_PASSWORD is required (set in .env or pass DB_PASS=...)" && exit 1)
	$(DB) mariadb -u $(DB_USER) -p'$(DB_PASS)' $(DB_NAME) -e \
		"INSERT INTO radcheck (username, attribute, op, value) \
		 VALUES ('$(USER)', 'Cleartext-Password', ':=', '$(PASS)');"
	@if [ -n "$(GROUP)" ]; then \
		$(DB) mariadb -u $(DB_USER) -p'$(DB_PASS)' $(DB_NAME) -e \
			"INSERT INTO radusergroup (username, groupname, priority) \
			 VALUES ('$(USER)', '$(GROUP)', 1);"; \
		echo "✅ User '$(USER)' added to group '$(GROUP)'"; \
	else \
		echo "✅ User '$(USER)' added (no group)"; \
	fi

list-users: ## List all users with their groups
	@test -n "$(DB_PASS)" || (echo "ERROR: DB_PASS or DB_PASSWORD is required (set in .env or pass DB_PASS=...)" && exit 1)
	$(DB) mariadb -u $(DB_USER) -p'$(DB_PASS)' $(DB_NAME) -e \
		"SELECT rc.username, rc.attribute, IFNULL(rug.groupname, '(none)') AS grp \
		 FROM radcheck rc \
		 LEFT JOIN radusergroup rug ON rc.username = rug.username \
		 ORDER BY rc.username;"

delete-user: ## Delete a user: make delete-user USER=jdoe
	@test -n "$(USER)" || (echo "ERROR: USER is required" && exit 1)
	@test -n "$(DB_PASS)" || (echo "ERROR: DB_PASS or DB_PASSWORD is required (set in .env or pass DB_PASS=...)" && exit 1)
	$(DB) mariadb -u $(DB_USER) -p'$(DB_PASS)' $(DB_NAME) -e \
		"DELETE FROM radcheck WHERE username='$(USER)'; \
		 DELETE FROM radreply WHERE username='$(USER)'; \
		 DELETE FROM radusergroup WHERE username='$(USER)';"
	@echo "✅ User '$(USER)' deleted."

# ---------------------------------------------------------------------------
# Shells
# ---------------------------------------------------------------------------

shell: ## Open a shell in the FreeRADIUS container
	docker exec -it freeradius /bin/bash

db-shell: ## Open a MariaDB CLI
	@test -n "$(DB_PASS)" || (echo "ERROR: DB_PASS or DB_PASSWORD is required (set in .env or pass DB_PASS=...)" && exit 1)
	docker exec -it radius-db mariadb -u $(DB_USER) -p'$(DB_PASS)' $(DB_NAME)

# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------

db-maintenance: ## Run accounting log cleanup
	$(DB) /bin/bash /opt/db-scripts/db-maintenance.sh

debug: ## Restart FreeRADIUS in debug mode (foreground, verbose)
	$(COMPOSE) stop freeradius
	$(COMPOSE) run --rm --service-ports freeradius freeradius -X

validate: ## Validate FreeRADIUS config without starting
	$(RADIUS) freeradius -CX

# ---------------------------------------------------------------------------
# Management UI
# ---------------------------------------------------------------------------

mgmt-up: ## Start daloRADIUS management interface
	$(COMPOSE) --profile management up -d daloradius
	@echo "daloRADIUS available at http://localhost:$${DALORADIUS_PORT:-8000}"

mgmt-down: ## Stop daloRADIUS
	$(COMPOSE) --profile management stop daloradius

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean: ## Remove all containers, volumes, and images
	$(COMPOSE) down -v --rmi local
	@echo "✅ All containers, volumes, and images removed."
