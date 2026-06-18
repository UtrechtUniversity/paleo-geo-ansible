# copyright Utrecht University
# Paleo WordPress image — a THIN layer on the official WordPress image.

FROM wordpress:6.7-php8.3-apache
LABEL maintainer="Paleo Earth <paleo-example@uu.nl>"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

EXPOSE 80 443

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Apache: enable TLS + headers (rewrite is already enabled in the base image)
RUN a2enmod ssl headers rewrite && \
    a2dissite 000-default
COPY 000-paleo-http.conf  /etc/apache2/sites-available/000-paleo-http.conf
COPY 001-paleo-https.conf /etc/apache2/sites-available/001-paleo-https.conf
COPY paleo-ssl.cnf        /etc/ssl/paleo-ssl.cnf
RUN a2ensite 000-paleo-http && a2ensite 001-paleo-https

# Paleo init runs first (host substitution + TLS cert), then hands off to the entrypoint
COPY paleo-init.sh /paleo-init.sh
RUN chmod 0755 /paleo-init.sh
ENTRYPOINT ["/paleo-init.sh"]
CMD ["apache2-foreground"]
