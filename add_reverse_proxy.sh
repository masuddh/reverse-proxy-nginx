#!/bin/bash

# Fungsi untuk menambah konfigurasi reverse proxy
add_reverse_proxy() {
    read -p "Enter domain name: " domain
    read -p "Enter backend service URL (e.g., http://backend:8080): " backend_service

    # Pastikan URL backend benar
    if [[ ! $backend_service =~ ^http:\/\/ ]]; then
        backend_service="http://$backend_service"
    fi

    conf_file="nginx/sites-available/${domain}.conf"

    cat > $conf_file <<EOL
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass $backend_service;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /.well-known/acme-challenge/ {
        root /data/letsencrypt;
    }
}

server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    location / {
        proxy_pass $backend_service;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

    # Hapus symbolic link jika sudah ada
    if [ -L "nginx/sites-enabled/${domain}.conf" ]; then
        rm "nginx/sites-enabled/${domain}.conf"
    fi

    # Membuat symbolic link baru
    ln -s ../sites-available/$domain.conf nginx/sites-enabled/

    # Restart Nginx untuk memuat konfigurasi baru
    docker-compose restart nginx

    # Tunggu beberapa detik agar Nginx benar-benar restart
    sleep 5

    # Mendapatkan sertifikat SSL dengan Certbot
    docker run -it --rm --name "certbot_$domain" \
      -v "$(pwd)/nginx/certs:/etc/letsencrypt" \
      -v "$(pwd)/nginx/certs-data:/data/letsencrypt" \
      certbot/certbot certonly --webroot --webroot-path=/data/letsencrypt \
      --email your-email@example.com --agree-tos --no-eff-email \
      -d $domain

    # Reload Nginx setelah mendapatkan sertifikat
    docker-compose exec nginx nginx -s reload
}

# Main script
while true; do
    echo "1. Add reverse proxy"
    echo "2. Exit"
    read -p "Choose an option: " choice

    case $choice in
        1)
            add_reverse_proxy
            ;;
        2)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
done
