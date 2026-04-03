# =============================================================================
# daloRADIUS — Web Management UI for FreeRADIUS
# =============================================================================
FROM debian:11-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-php \
        php \
        php-mysql \
        php-gd \
        php-curl \
        php-mail \
        php-mail-mime \
        php-mbstring \
        php-db \
        php-zip \
        php-common \
        php-cli \
        mariadb-client \
        freeradius-utils \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone daloRADIUS
RUN git clone --depth 1 https://github.com/lirantal/daloradius.git /var/www/daloradius \
    && chown -R www-data:www-data /var/www/daloradius

# Apache virtual hosts
COPY apache-operators.conf /etc/apache2/sites-available/operators.conf
COPY apache-users.conf /etc/apache2/sites-available/users.conf
RUN a2dissite 000-default && a2ensite operators users && a2enmod rewrite

# Entrypoint for DB config injection
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apachectl", "-D", "FOREGROUND"]
