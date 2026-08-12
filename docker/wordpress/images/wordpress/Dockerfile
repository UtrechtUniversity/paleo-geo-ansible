# copyright Utrecht University
# Paleo WordPress image — a THIN layer on the official WordPress image.

FROM wordpress:6.7-php8.3-apache
LABEL maintainer="Paleo Earth <paleo-example@uu.nl>"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Documentation only. Plain HTTP backend behind the reverse proxy.
EXPOSE 80

# Swap the stock vhost for our plain-HTTP WordPress vhost.
RUN a2dissite 000-default
COPY 000-paleo-http.conf /etc/apache2/sites-available/000-paleo-http.conf
RUN a2ensite 000-paleo-http

# Paleo init substitutes the hostname into the vhost.
COPY paleo-init.sh /paleo-init.sh
RUN chmod 0755 /paleo-init.sh
ENTRYPOINT ["/paleo-init.sh"]
CMD ["apache2-foreground"]
