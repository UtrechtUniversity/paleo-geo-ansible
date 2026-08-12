# copyright Utrecht University
# Nginx reverse proxy for the Paleo sites.

# Minor version pin, stable version.
FROM nginx:1.27

# No runtime effect.
LABEL org.opencontainers.image.authors="Paleo Earth / Utrecht University"

# Remove initial conf, later we write our own.
RUN rm -f /etc/nginx/conf.d/default.conf

COPY templates/redirect.conf      /etc/nginx/templates/redirect.conf
COPY templates/site.conf.template /etc/nginx/templates/site.conf.template
COPY paleo-ssl.cnf                /etc/nginx/templates/paleo-ssl.cnf

COPY nginx-entrypoint.sh /nginx-entrypoint.sh
RUN chmod 0755 /nginx-entrypoint.sh

CMD ["/nginx-entrypoint.sh"]
