# copyright Utrecht University

# Slim is a minimal image type
# Debian is what the wp image uses officially, to retain the similarity of both static and wp sites
FROM debian:12-slim
LABEL maintainer="Paleo Earth <paleo-example@uu.nl>"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Documentation only
EXPOSE 80 443

# Openssl is needed for making self-signed certs
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apache2 openssl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Rewrite: redirect HTTP->HTTPS
RUN a2enmod ssl headers rewrite && \
    a2dissite 000-default

COPY 000-paleo-http.conf  /etc/apache2/sites-available/000-paleo-http.conf
COPY 001-paleo-https.conf /etc/apache2/sites-available/001-paleo-https.conf
COPY paleo-ssl.cnf        /etc/ssl/paleo-ssl.cnf
# Create symlinks in sites-enabled/ for two vhosts
RUN a2ensite 000-paleo-http && a2ensite 001-paleo-https

# Demo content — baked into the image for the MVP. Replace per site later.
COPY index.html /var/www/html/index.html
RUN chown -R www-data:www-data /var/www/html

COPY paleo-init.sh /paleo-init.sh
RUN chmod 0755 /paleo-init.sh

# CMD instructs the execution when the container runs, not in build time
CMD ["/paleo-init.sh"]
