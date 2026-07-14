#!/bin/bash
# ============================================================
# app_setup.sh — Installs Docker + Tomcat app on App EC2
# Called by Terraform user_data on App instance
# ============================================================

set -e
exec > /var/log/app_setup.log 2>&1

DB_ENDPOINT="${db_endpoint}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
NEXUS_URL="${nexus_url}"

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Pull and run Tomcat app container
# In real pipeline, Jenkins will push image to ECR/Nexus and deploy here
docker run -d \
  --name vproapp \
  --restart always \
  -p 8080:8080 \
  -e DB_HOST="$DB_ENDPOINT" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASS="$DB_PASSWORD" \
  tomcat:10-jdk21

echo "App server setup complete. Tomcat running on :8080"
echo "DB Endpoint: $DB_ENDPOINT"