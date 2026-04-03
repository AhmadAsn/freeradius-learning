# =============================================================================
# FreeRADIUS 3.x — Production Docker Image
# =============================================================================
FROM freeradius/freeradius-server:latest-3.2

USER root

# Install additional tools needed by entrypoint & healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
        mariadb-client \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Ensure log directory exists with correct ownership
RUN mkdir -p /var/log/freeradius \
    && chown -R freerad:freerad /var/log/freeradius

# Ensure certs directory
RUN mkdir -p /etc/raddb/certs \
    && chown -R freerad:freerad /etc/raddb/certs

# Copy entrypoint and healthcheck
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh /opt/radius-scripts/healthcheck.sh
COPY scripts/generate-certs.sh /opt/radius-scripts/generate-certs.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
              /opt/radius-scripts/healthcheck.sh \
              /opt/radius-scripts/generate-certs.sh

EXPOSE 1812/udp 1813/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
