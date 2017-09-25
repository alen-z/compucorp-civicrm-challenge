# Official Debian image https://hub.docker.com/_/debian/
FROM debian:jessie

# Additional metadata
MAINTAINER Alen Zubic <alen.zubich@gmail.com>

ENV CIVICRM_VERSION 4.7.24
ENV DRUPAL_VERSION 7.56
ENV NGINX_VERSION 1.6.2*

# Avoid ERROR: invoke-rc.d: policy-rc.d denied execution of start.
RUN sed -i "s/^exit 101$/exit 0/" /usr/sbin/policy-rc.d

# Backports for certbot
RUN echo "deb http://ftp.debian.org/debian jessie-backports main" >> /etc/apt/sources.list

# Get updates & install packages
RUN apt-get update && apt-get install -y \
    curl \
    drush \
    git \
    mysql-client \
    nginx=$NGINX_VERSION \
    php5 \
    php5-curl \
    php5-fpm \
    php5-gd \
    php5-mysql \
    tar \
    vim

# Install certbot from backports
RUN apt-get install -y certbot -t jessie-backports

# Remove public web nginx dummy files and download Drupal (can be done with drush)
WORKDIR /var/www/html
RUN rm -rf * && \
    git clone -b $DRUPAL_VERSION https://github.com/drupal/drupal.git && \
    chown -R www-data:www-data .

# Download CiviCRM
WORKDIR /var/www/html/drupal/sites/all/modules
RUN curl -o civicrm-$CIVICRM_VERSION-drupal.tar.gz -v https://storage.googleapis.com/civicrm/civicrm-stable/$CIVICRM_VERSION/civicrm-$CIVICRM_VERSION-drupal.tar.gz
RUN chmod 755 civicrm-$CIVICRM_VERSION-drupal.tar.gz && \
    tar zxf civicrm-$CIVICRM_VERSION-drupal.tar.gz && \
    chown -R www-data:www-data civicrm && \
    rm civicrm-$CIVICRM_VERSION-drupal.tar.gz

# Put yummy files into container
COPY drushrc.php                        /etc/drush
COPY nginx.conf                         /etc/nginx/
COPY default                            /etc/nginx/sites-available/
COPY default_ssl                        /etc/nginx/sites-available/
COPY www.conf                           /etc/php5/fpm/pool.d/
COPY settings_php_civicrm_update.txt    /
COPY start.sh                           /

# Modify lovely permissions
RUN chmod u+x /start.sh

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Ensures variable pass when running Docker
ENTRYPOINT ["/start.sh"]

# Start nginx and keep Docker alive by dumping nginx logs
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]