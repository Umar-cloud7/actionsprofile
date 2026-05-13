#!/bin/bash
# ============================================================
# cicd_setup.sh — Installs Jenkins + Nexus + SonarQube via Docker
# Called by Terraform user_data on CI/CD instance
# ============================================================

set -e
exec > /var/log/cicd_setup.log 2>&1

# Update system
yum update -y

# Install Docker + Docker Compose
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create docker-compose for CI/CD stack
mkdir -p /opt/cicd
cat > /opt/cicd/docker-compose.yml <<'EOF'
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts-jdk21
    container_name: jenkins
    restart: always
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - JAVA_OPTS=-Djenkins.install.runSetupWizard=false

  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    restart: always
    ports:
      - "8081:8081"
    volumes:
      - nexus_data:/nexus-data
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Xms512m -Xmx1200m

  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    restart: always
    ports:
      - "9000:9000"
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_logs:/opt/sonarqube/logs
    environment:
      - SONAR_JDBC_URL=jdbc:postgresql://sonardb:5432/sonar
      - SONAR_JDBC_USERNAME=sonar
      - SONAR_JDBC_PASSWORD=sonarpass
    depends_on:
      - sonardb

  sonardb:
    image: postgres:15
    container_name: sonardb
    restart: always
    volumes:
      - sonardb_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=sonar
      - POSTGRES_PASSWORD=sonarpass
      - POSTGRES_DB=sonar

volumes:
  jenkins_home:
  nexus_data:
  sonar_data:
  sonar_logs:
  sonardb_data:
EOF

# Start CI/CD stack
cd /opt/cicd
docker-compose up -d

echo "CI/CD stack started"
echo "Jenkins  : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "Nexus    : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "SonarQube: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"