#!/bin/bash
# ============================================================
# nginx_setup.sh — Installs Docker + Nginx container on Web EC2
# Called by Terraform user_data on Nginx instance
# ============================================================

set -e
exec > /var/log/nginx_setup.log 2>&1

APP_PRIVATE_IP="${app_private_ip}"   # Injected by Terraform templatefile

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Create Nginx config pointing to Tomcat backend
cat > /tmp/vproapp.conf <<EOF
upstream vproapp {
    server $APP_PRIVATE_IP:8080;
}

server {
    listen 80;

    location / {
        proxy_pass http://vproapp;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Run Nginx container with custom config
docker run -d \
  --name nginx \
  --restart always \
  -p 80:80 \
  -v /tmp/vproapp.conf:/etc/nginx/conf.d/vproapp.conf:ro \
  nginx:latest

echo "Nginx setup complete. Proxying to $APP_PRIVATE_IP:8080"