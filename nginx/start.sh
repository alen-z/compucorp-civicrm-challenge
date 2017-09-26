#!/bin/bash

# Config variables
LETSENCRYPT_CHALLENGE_DIR=/var/www/letsencrypt
LETSENCRYPT_LIVE_DIR=/etc/letsencrypt/live
POKE=/.poke
WWW_DIR=/var/www/html/drupal

start_php () {

    #####################
    # PHP-FPM daemon    #
    #####################

    # Recommended fix from official PHP site for NGINX
    sed -i "s/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini

    # Start PHP daemon
    service php5-fpm start

}

set_SSL () {

    #################################
    # Certificates                  #
    #################################

    # Start temporary web service
    service nginx start

    # Prepare challenge directory
    mkdir $LETSENCRYPT_CHALLENGE_DIR && \
        chgrp www-data $LETSENCRYPT_CHALLENGE_DIR && \
        chmod g=rx $LETSENCRYPT_CHALLENGE_DIR

    # Fetch certificate
    certbot certonly --webroot \
        -w $LETSENCRYPT_CHALLENGE_DIR \
        -d $SITE_DOMAIN \
        -m $LETSENCRYPT_MAIL \
        --agree-tos
        # --staging
        # --rsa-key-size 4096

    # Stop temporary web service
    service nginx stop

    # 4096 takes a long time so this is for speed purposes
    openssl dhparam 2048 -out /etc/ssl/dhparam.pem

    # Apply SSL nginx config if we got the certificate. Condition
    # is validated against folder that should exist in case of success
    if [ -d "$LETSENCRYPT_LIVE_DIR" ]; then
        mv /etc/nginx/sites-available/default_ssl /etc/nginx/sites-available/default
        sed -i "s/compucorp.zaay.io/$SITE_DOMAIN/g" /etc/nginx/sites-available/default
    fi

}

site_install () {

    #########################
    # Drupal installation   #
    #########################

    # Install Drupal
    drush site-install standard -y \
        --db-url="mysql://$DRUPAL_DB_USER:$DRUPAL_DB_PASS@$DRUPAL_DB_HOST/$DRUPAL_DB_NAME" \
        --site-name="$DRUPAL_SITE_NAME" \
        --account-name=$DRUPAL_SITE_USER \
        --account-pass=$DRUPAL_SITE_PASS

    # Update Drupal site configuration file. An attacker could exploit a missing $base_url setting.
    sed -i "s/^# \$base_url = 'http:\/\/www.example.com'/# \$base_url = 'http:\/\/$SITE_DOMAIN'/" $WWW_DIR/sites/default/settings.php

    # Patch CiviCRM+Views integration. IMPORTANT: Clear all cache in web UI!
    cat /settings_php_civicrm_update.txt >> $WWW_DIR/sites/default/settings.php

    # Set default site permissions
    chmod 755 $WWW_DIR/sites/default

    #########################
    # Enable CiviCRM        #
    #########################

    # Copy dummy civicrm.settings.php just to enable module
    cp $WWW_DIR/sites/all/modules/civicrm/templates/CRM/common/civicrm.settings.php.template \
        $WWW_DIR/sites/default/civicrm.settings.php

    # Throws an error but CiviCRM stays enabled for civicrm-install to work
    drush en civicrm -y    2>/dev/null

    # CiviCRM install - DB & civicrm.settings.php
    drush civicrm-install \
        --site_url=$SITE_DOMAIN \
        --dbhost=$CIVICRM_DB_HOST \
        --dbname=$CIVICRM_DB_NAME \
        --dbuser=$CIVICRM_DB_USER \
        --dbpass=$CIVICRM_DB_PASS \
        --ssl=on

    # Re-enable CiviCRM to get side link in Drupal etc.
    drush dis civicrm -y && \
        drush en civicrm civicrmtheme -y

    #############################
    # Other Drupal dependencies #
    #############################

    # Install Views3
    drush dl views-7.x-3.18 && \
        drush en views views_ui -y

    # Install Backup and Migrate
    drush dl backup_migrate-7.x-3.x    && \
        drush en backup_migrate -y

    # Get S3 PHP lib for Backup and Migrate to work with Amazon S3
    git clone https://github.com/tpyo/amazon-s3-php-class.git \
        $WWW_DIR/sites/all/modules/backup_migrate/includes/s3-php5-curl

}

mysql_wait_until_live () {

    # Wait for MySQL to come alive!
    SQL_ALIVE=0
    while [ $SQL_ALIVE -eq 0 ]
    do
        # Put stderr in variable for evaluation
        SQL_CONN=$(mysql -h $DRUPAL_DB_HOST -u $DRUPAL_DB_USER -p$DRUPAL_DB_PASS -e "exit" 2>&1)
        echo "Waiting for MySQL to come alive (testing for '$DRUPAL_DB_USER' user on '$DRUPAL_DB_HOST' host)..."
        if [[ $SQL_CONN != ERROR* ]]; then
            # We are alive. From now on we can use MySQL.
            echo "Database ready!"
            SQL_ALIVE=1
        fi
        # Check every 1s
        sleep 1
    done

}

tighten_security () {

    #####################
    # Introduce user    #
    #####################

    # Create user with home directory
    useradd -m $SYSTEM_USER

    # Set user password
    chpasswd <<< "$SYSTEM_USER:$SYSTEM_PASS"

    #########################
    # Drupal private folder #
    #########################

    PRIVATE_FILES_DIR=/home/$SYSTEM_USER/files_private

    # Create private folder in user's home directory
    su - drupal -c "mkdir $PRIVATE_FILES_DIR"

    # Allow Drupal/nginx to manage it
    chgrp www-data $PRIVATE_FILES_DIR && \
        chmod g=rwx $PRIVATE_FILES_DIR

    # Tell Drupal where to find private directory
    drush vset file_private_path $PRIVATE_FILES_DIR -y

    #############################
    # Drupal - other concerns   #
    #############################

    # Do not show errors in production. Possible full path disclosure.
    drush vset error_level 0

    # User owns the site and nginx can access them, but not write
    chown -R drupal:www-data $WWW_DIR && \
        chmod -R g=rx,o= $WWW_DIR

    # 'files' directory is an exception
    chmod -R g=rwx $WWW_DIR/sites/default/files

    # Fix unnecessary Drupal error occurring because we
    # force SSL and it can't get http request back
    echo "\$conf['drupal_http_request_fails'] = FALSE;" >> $WWW_DIR/sites/default/settings.php

}

start_php

# Build application content only for the first time. Service up/stop now works.
if [ ! -f "$POKE" ]; then
    # Remember we were here
    touch $POKE

    # Get certificate and put nginx configuration in place
    set_SSL

    # Wait to get MySQL connection
    mysql_wait_until_live

    # Install Drupal, CiviCRM & other dependencies
    site_install

    # Introduce new user and apply best practices
    tighten_security
fi

# Print ready message
echo "$SITE_DOMAIN is ready"

# Check if Docker came with arguments
if [ ! $# -eq 0 ]; then
    # Exit on error from now on
    set -e

    # Execute Docker commands if given
    exec "$@"
fi