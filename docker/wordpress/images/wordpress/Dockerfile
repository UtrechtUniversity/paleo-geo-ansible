# copyright Utrecht University
# Custom WordPress image — Apache + PHP 8.3 + WordPress + WP-CLI.
# To retain the control on OS layer.
# NOTE ON BASE IMAGE TAG: `php:8.3-apache-bookworm` pins to Debian 12 (Bookworm).
# The `php:8.3-apache` recently moved to Debian 13 (Trixie), which has issue in running xz cmd.

FROM php:8.3-apache-bookworm
LABEL maintainer="Paleo Earth <paleo-example@uu.nl>"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV WORDPRESS_VERSION="6.7.1"
ENV WP_CLI_ALLOW_ROOT=0

EXPOSE 80 443

# OS-level dependencies and PHP build-time libraries.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates sudo less vim-tiny openssl \
        default-mysql-client \
        libpng-dev libjpeg-dev libfreetype6-dev \
        libonig-dev libxml2-dev libzip-dev && \
    rm -rf /var/lib/apt/lists/*

# WordPress-required PHP extensions.
RUN docker-php-ext-configure gd --with-jpeg --with-freetype && \
    docker-php-ext-install -j"$(nproc)" \
        mysqli \
        gd \
        mbstring \
        xml \
        zip \
        opcache

# Apache modules
RUN a2enmod ssl headers rewrite && \
    a2dissite 000-default

COPY 000-paleo-http.conf  /etc/apache2/sites-available/000-paleo-http.conf
COPY 001-paleo-https.conf /etc/apache2/sites-available/001-paleo-https.conf
COPY paleo-ssl.cnf        /etc/ssl/paleo-ssl.cnf
RUN a2ensite 000-paleo-http && a2ensite 001-paleo-https

# WordPress core, pinned
RUN rm -rf /var/www/html/* && \
    curl -fsSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz" | \
        tar -xz -C /var/www/html --strip-components=1 && \
    chown -R www-data:www-data /var/www/html

# WP-CLI for WordPress auto installation
# Checksum verified (needed?)
RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /usr/local/bin/wp && \
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512 \
        -o /tmp/wp-cli.phar.sha512 && \
    echo "$(cat /tmp/wp-cli.phar.sha512)  /usr/local/bin/wp" | sha512sum -c - && \
    rm /tmp/wp-cli.phar.sha512 && \
    chmod +x /usr/local/bin/wp

COPY paleo-init.sh /paleo-init.sh
RUN chmod 0755 /paleo-init.sh

CMD ["/paleo-init.sh"]
