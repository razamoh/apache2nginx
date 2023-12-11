#!/bin/bash

APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# Loop through Apache sites-available, excluding specific files
for APACHE_CONF in "$APACHE_SITES_AVAILABLE"/*.conf; do
    # Exclude specific files
    case "$(basename "$APACHE_CONF")" in
        000-default.conf | default.conf | default-ssl.conf)
            continue ;;
    esac

    # Check if the file has a .conf extension
    if [ ! "$(echo "$APACHE_CONF" | grep '\.conf$')" ]; then
        echo "Skipping $APACHE_CONF as it does not have a .conf extension."
        continue
    fi

    if [ -s "$APACHE_CONF" ]; then
        # Extract relevant information from Apache configuration
        SERVER_NAME=$(grep -i '^[^#]*ServerName' "$APACHE_CONF" | awk '{$1=""; gsub(/^[ \t]+|[ \t]+$/, "", $0); print $0; exit}')
        echo "ABC - ${SERVER_NAME}"
        DOCUMENT_ROOT=$(awk '/DocumentRoot/ {print $2; exit}' "$APACHE_CONF")

        # Check if SERVER_NAME is empty or contains only non-alphanumeric characters
        if [ -z "$SERVER_NAME" ]; then
            echo "Error: Invalid SERVER_NAME for $APACHE_CONF. Skipping conversion."
            continue
        fi

        # Generate Nginx configuration for HTTP
        NGINX_CONF_HTTP="$NGINX_SITES_AVAILABLE/$SERVER_NAME.conf"
        cat <<EOF >"$NGINX_CONF_HTTP"
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAME};
    root /var/www/html/${SERVER_NAME}/;
    index index.php index.html index.htm;

    # Logging
    access_log /var/log/nginx/${SERVER_NAME}_access.log;
    error_log /var/log/nginx/${SERVER_NAME}_error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    # PHP configurations
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.0-fpm.sock; # Adjust the PHP version and socket path as needed
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    ssl_certificate /etc/letsencrypt/live/${SERVER_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SERVER_NAME}/privkey.pem;
}

server {
    if (\$host = www.${SERVER_NAME}) {
        return 301 https://$host$request_uri;
    }

    if (\$host = ${SERVER_NAME}) {
        return 301 https://$host$request_uri;
    }

    listen 80;
    listen [::]:80;

    server_name www.${SERVER_NAME} ${SERVER_NAME};
    return 404;
}
EOF

        # Create symbolic links in Nginx sites-enabled
        ln -sf "$NGINX_CONF_HTTP" "$NGINX_SITES_ENABLED/"
    fi
done

# Test Nginx configuration and reload
echo "Testing Nginx configuration..."
nginx -t
if [ $? -eq 0 ]; then
    echo "Nginx configuration test passed. Reloading Nginx..."
    systemctl reload nginx
    echo "Nginx reloaded."
else
    echo "Nginx configuration test failed. Please check the configuration and try again."
fi

echo "Conversion completed!"
