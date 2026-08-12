# copyright Utrecht University

# Slim is a minimal image type.
# Debian matches the official WordPress image, keeping static and wp similar.
FROM debian:12-slim
LABEL maintainer="Paleo Earth <paleo-example@uu.nl>"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Documentation only. TLS is terminated by the paleo-nginx reverse proxy, so
# this container serves plain HTTP on port 80 only.
EXPOSE 80

RUN apt-get update && \
    apt-get install -y --no-install-recommends apache2 && \
    rm -rf /var/lib/apt/lists/*

RUN a2dissite 000-default

COPY 000-paleo-http.conf /etc/apache2/sites-available/000-paleo-http.conf
RUN a2ensite 000-paleo-http

# Demo content — baked into the image for the MVP. Replace per site later.
COPY index.html /var/www/html/index.html
RUN chown -R www-data:www-data /var/www/html

CMD ["apache2ctl", "-DFOREGROUND"]
