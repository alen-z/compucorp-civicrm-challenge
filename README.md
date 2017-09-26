# Compucorp CiviCRM challenge
Docker deployment of Drupal 7 with CiviCRM

# Run our site
Please find the demo at: https://compucorp.zaay.io

Quickstart (while in docker-compose.yml directory):
```
docker-compose up
```
All pre-configured variables are set in site.env. Please take a look at the file prior to running. If we leave it as-is please refer to the file for Drupal login credentials.

> IMPORTANT: If site domain is not reachable NGINX will use port http:80 without Let's Encrypt certificate for SSL on https:443.

Run site with custom site.env settings:
```
SITE_DOMAIN=your.domain.com
LETSENCRYPT_MAIL=your@mail.com
DRUPAL_SITE_NAME=Example title
DRUPAL_SITE_USER=username
DRUPAL_SITE_PASS=password
DRUPAL_DB_HOST=drupal_db.hostname.com
DRUPAL_DB_NAME=drupal_db_name
DRUPAL_DB_USER=drupal_db_username
DRUPAL_DB_PASS=drupal_db_password
CIVICRM_DB_HOST=civicrm_db.hostname.com
CIVICRM_DB_NAME=civicrm_db_name
CIVICRM_DB_USER=civicrm_db_username
CIVICRM_DB_PASS=civicrm_db_username
SYSTEM_USER=debian_username
SYSTEM_PASS=debian_password
```

# Quick rundown
Get MySQL database ready (ex. mysql/startup.sql) and provide docker-compose with required parameters. Running application when SITE_DOMAIN is not reachable for certbot (Let's Encrypt), NGINX with basic configuration is deployed on port 80 w/o SSL.

# Drupal 7 on Debian
Official <code>apt-get install drupal7</code> (https://wiki.debian.org/Drupal) uses Apache so we need to configure it manually for NGINX.

* Drupal user can run all drush commands
* Drupal private directory path is in user's home with sufficient permissions for Drupal access
* Not showing any errors in producton. An attacker could exploit a missing <code>$base_url</code> setting so it is included in Drupal settings.php
* Drupal files folder needs to be writable
* Removed permissions for other users.


Default login:
```
Username: admin
Password: caLL@!2
```
> IMPORTANT: Clear all cache from Administration panel is needed for Views to work with CiviCRM after first run.

# PHP
We'll go with php-fpm (http://php.net/manual/en/install.fpm.php) for its additional features. <code>cgi.fix_pathinfo=0</code> is taken into account (http://php.net/manual/en/install.unix.nginx.php). Memory limit (128M) in php.ini should be fine (https://www.drupal.org/docs/7/managing-site-performance-and-scalability/changing-php-memory-limits, https://www.drupal.org/docs/7/system-requirements/php#memory).

# CiviCRM
More modular approach could be used with <code>drush make</code> but <code>drush civicrm-install</code> is cool nonetheless.

# SSL (https)
Certificates are managed by certbot which automates Let's Encrypt certificate fetching and renewal. In case of error it stays on nginx/default configuration, http:80. Please use <code>--staging</code> flag in nginx/start.sh if you go out of production certificates.

# NGINX
Master process is started as root but workers are started as www-data as expected so we are good (possible tightening is available https://unix.stackexchange.com/a/134303). Site configuration file is build using best practices for using Drupal, CiviCRM, general security and good SSL Labs score.

# DB
Prior to running Docker services it is necessary to automate implementing mysql/startup.sql. This is now done in <code>docker-compose.yml</code> for <code>db</code> service.
In production we would want to use database with data mounted outside of the container. Official MySQL Docker hub image is used only for demo purposes.

# Docker
Some of the possible improvements:
* Unable to change only NGINX config with Docker commands w/o re-deploying complete application.
* Automate Amazon S3 backup using three variables: bucket name, access key ID and secret

# AWS
Amazon S3 bucket is in US East (N. Virginia) to use Drupal Backup and Migrate Amazon S3 feature.

Created compucorp-user-bm user using Amazon IAM console w/o permissions, only with access key. S3 bucket compucorp-s3-bm has policy:
```JSON
{
    "Version": "2012-10-17",
    "Id": "compucorp-access-backup",
    "Statement": [
        {
            "Sid": "CompucorpObjectManagement",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::008593290623:user/compucorp-user-bm"
            },
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::compucorp-s3-bm/*"
        },
        {
            "Sid": "CompucorpBucketManagement",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::008593290623:user/compucorp-user-bm"
            },
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::compucorp-s3-bm"
        }
    ]
}
```

# Backup
Full site - Restore and backup are completed within ~30s. If S3 bucket size is a problem then CiviCRM database is a priority. Keeping daily backups for a month would take 6GB+ in a bucket.