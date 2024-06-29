#!/bin/bash

# Prompt the user for the domain name
read -p "Enter your domain name (e.g., mysite.local): " DOMAIN

# Prompt the user for the IP address of the backend server
read -p "Enter the IP address of your backend server: " BACKEND_IP

# Prompt the user for the port number (default to 80)
read -p "Enter the port number (default is 80): " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-80}

# Update package list
sudo apt update

# Install Nginx if not already installed
if ! command -v nginx &> /dev/null; then
    sudo apt install -y nginx
fi

# Install mkcert if not already installed
if ! command -v mkcert &> /dev/null; then
    sudo apt install -y libnss3-tools
    wget -O mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-amd64
    chmod +x mkcert
    sudo mv mkcert /usr/local/bin/
    mkcert -install
fi

# Create directories for SSL if not already existing
sudo mkdir -p /etc/nginx/ssl

# Generate certificates using mkcert
mkcert -cert-file /etc/nginx/ssl/$DOMAIN.pem -key-file /etc/nginx/ssl/$DOMAIN-key.pem $DOMAIN "*.$DOMAIN"

# Create Nginx configuration file for the domain
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
if [ ! -f "$NGINX_CONF" ]; then
    sudo bash -c "cat > $NGINX_CONF" <<EOL
server {
    listen 80;  # Listen for HTTP requests on port 80
    server_name $DOMAIN;  # Your domain name

    location / {
        proxy_pass http://$BACKEND_IP:$BACKEND_PORT;  # Proxy pass to the backend server
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
fi

# Enable the new site
if [ ! -f "/etc/nginx/sites-enabled/$DOMAIN" ]; then
    sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
fi

# Create Nginx snippets for SSL configuration
sudo bash -c "cat > /etc/nginx/snippets/mkcert.conf" <<EOL
ssl_certificate /etc/nginx/ssl/$DOMAIN.pem;
ssl_certificate_key /etc/nginx/ssl/$DOMAIN-key.pem;
EOL

sudo bash -c "cat > /etc/nginx/snippets/ssl-params.conf" <<EOL
ssl_protocols TLSv1.2;
ssl_prefer_server_ciphers on;
ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
ssl_ecdh_curve secp384r1;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
EOL

# Update Nginx configuration for SSL
sudo bash -c "cat >> $NGINX_CONF" <<EOL

server {
    listen 443 ssl;  # Listen for HTTPS requests on port 443
    server_name $DOMAIN;  # Your domain name

    include snippets/mkcert.conf;  # Include the SSL certificate paths
    include snippets/ssl-params.conf;  # Include additional SSL parameters

    location / {
        proxy_pass http://$BACKEND_IP:$BACKEND_PORT;  # Proxy pass to the backend server
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# Test Nginx configuration
sudo nginx -t

# Start or reload Nginx
if sudo systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
else
    sudo systemctl start nginx
fi

# Output success message
echo "Setup complete. Your domain $DOMAIN should now be accessible via HTTPS."
