#!/bin/bash
#
# Script de instalação automatizada do GLPI 10 no Debian 13 (Trixie)
#

echo "#########################################################"
echo " Script para Instalacao do GLPI no Debian 13 (Trixie)"
echo "#########################################################"

# 1. Atualiza a lista de pacotes disponíveis no repositório.
sudo apt update && sudo apt upgrade -y

# 2. Instala softwares necessários
sudo apt install -y \
  nginx \
  mariadb-server \
  mariadb-client \
  php-fpm \
  php-cli \
  php-common \
  php-mysql \
  php-xml \
  php-curl \
  php-gd \
  php-intl \
  php-bz2 \
  php-zip \
  php-exif \
  php-ldap \
  php-opcache \
  php-mbstring \
  php-apcu \
  wget tar

# 3. Criar banco de dados do GLPI
sudo mysql -e "CREATE DATABASE glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
sudo mysql -e "GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost' IDENTIFIED BY '1cd73cddc8dad1fef981391f'"
sudo mysql -e "GRANT SELECT ON mysql.time_zone_name TO 'glpi'@'localhost'"
sudo mysql -e "FLUSH PRIVILEGES"

# 4. Carregar timezones no MySQL
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -u root mysql

# 5. Ajusta php.ini (PHP 8.4 no Debian 13)
sudo sed -i 's/^;*session.cookie_httponly =.*/session.cookie_httponly = On/' /etc/php/8.4/fpm/php.ini
sudo sed -i 's/^;*date.timezone =.*/date.timezone = America\/Sao_Paulo/' /etc/php/8.4/fpm/php.ini

# 6. Configuração básica do Nginx para o GLPI
cat << "EOF" > /tmp/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events {
    worker_connections 768;
}
http {
    sendfile on;
    tcp_nopush on;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    server {
        listen 80;
        server_name _;
        root /var/www/glpi/public;
        index index.php;
        location / {
            try_files $uri /index.php$is_args$args;
        }
        location ~ ^/index\.php$ {
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/run/php/php8.4-fpm.sock;
            fastcgi_index index.php;
            include /etc/nginx/fastcgi.conf;
        }
    }
}
EOF
sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf

# 7. Reinicia os serviços necessários
sudo systemctl restart nginx php8.4-fpm mariadb

# 8. Download do GLPI
wget https://github.com/glpi-project/glpi/releases/download/10.0.20/glpi-10.0.20.tgz

# 9. Descompactar a pasta do GLPI
tar -zxf glpi-*.tgz

# 10. Mover a pasta do GLPI para /var/www
sudo mv glpi /var/www/glpi

# 11. Configura permissões iniciais
sudo chown -R www-data:www-data /var/www/glpi

# 12. Instalação via console (opcional, pode ser feita via web também)
sudo php /var/www/glpi/bin/console db:install \
  --default-language=pt_BR \
  --db-host=localhost \
  --db-port=3306 \
  --db-name=glpi \
  --db-user=glpi \
  --db-password=1cd73cddc8dad1fef981391f \
  --no-interaction

# 13. Ajustes de Segurança
## Remover o arquivo de instalação
sudo rm /var/www/glpi/install/install.php

## Mover diretórios sensíveis
sudo mv /var/www/glpi/files /var/lib/glpi
sudo mv /var/www/glpi/config /etc/glpi
sudo mkdir /var/log/glpi
sudo chown -R www-data:www-data /var/lib/glpi /etc/glpi /var/log/glpi

## Criar symlinks para compatibilidade
sudo ln -s /var/lib/glpi /var/www/glpi/files
sudo ln -s /etc/glpi /var/www/glpi/config

## Criar downstream.php
cat << "EOF" > /tmp/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
   require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF
sudo mv /tmp/downstream.php /var/www/glpi/inc/downstream.php

## Criar local_define.php
cat << "EOF" > /tmp/local_define.php
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_DOC_DIR', GLPI_VAR_DIR);
define('GLPI_CRON_DIR', GLPI_VAR_DIR . '/_cron');
define('GLPI_DUMP_DIR', GLPI_VAR_DIR . '/_dumps');
define('GLPI_GRAPH_DIR', GLPI_VAR_DIR . '/_graphs');
define('GLPI_LOCK_DIR', GLPI_VAR_DIR . '/_lock');
define('GLPI_PICTURE_DIR', GLPI_VAR_DIR . '/_pictures');
define('GLPI_PLUGIN_DOC_DIR', GLPI_VAR_DIR . '/_plugins');
define('GLPI_RSS_DIR', GLPI_VAR_DIR . '/_rss');
define('GLPI_SESSION_DIR', GLPI_VAR_DIR . '/_sessions');
define('GLPI_TMP_DIR', GLPI_VAR_DIR . '/_tmp');
define('GLPI_UPLOAD_DIR', GLPI_VAR_DIR . '/_uploads');
define('GLPI_CACHE_DIR', GLPI_VAR_DIR . '/_cache');
define('GLPI_LOG_DIR', '/var/log/glpi');
EOF
sudo mv /tmp/local_define.php /etc/glpi/local_define.php

# 14. Ajustar permissões finais
sudo chown -R root:root /var/www/glpi
sudo chown -R www-data:www-data /var/www/glpi/marketplace
sudo chown -R www-data:www-data /etc/glpi /var/lib/glpi /var/log/glpi

sudo find /var/www/glpi -type f -exec chmod 0644 {} \;
sudo find /var/www/glpi -type d -exec chmod 0755 {} \;
sudo find /etc/glpi -type f -exec chmod 0644 {} \;
sudo find /etc/glpi -type d -exec chmod 0755 {} \;
sudo find /var/lib/glpi -type f -exec chmod 0644 {} \;
sudo find /var/lib/glpi -type d -exec chmod 0755 {} \;
sudo find /var/log/glpi -type f -exec chmod 0644 {} \;
sudo find /var/log/glpi -type d -exec chmod 0755 {} \;

# 15. Fim
echo "#########################################################"
echo " INSTALACAO FINALIZADA COM SUCESSO."
echo " Acesse o GLPI via navegador: http://<ip-do-servidor>/"
echo "#########################################################"
