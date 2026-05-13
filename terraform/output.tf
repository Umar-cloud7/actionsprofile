# ============================================================
# outputs.tf — Useful values printed after terraform apply
# ============================================================

output "alb_dns_name" {
  description = "Application Load Balancer DNS — paste this in browser to access app"
  value       = aws_lb.vprofile_alb.dns_name
}

output "nginx_public_ip" {
  description = "Nginx web server public IP"
  value       = aws_instance.nginx.public_ip
}

output "app_private_ip" {
  description = "Tomcat app server private IP"
  value       = aws_instance.app.private_ip
}

output "cicd_public_ip" {
  description = "CI/CD server public IP — access Jenkins at :8080, Nexus at :8081, SonarQube at :9000"
  value       = aws_instance.cicd.public_ip
}

output "jenkins_url" {
  description = "Jenkins UI URL"
  value       = "http://${aws_instance.cicd.public_ip}:8080"
}

output "nexus_url" {
  description = "Nexus Repository Manager URL"
  value       = "http://${aws_instance.cicd.public_ip}:8081"
}

output "sonarqube_url" {
  description = "SonarQube UI URL"
  value       = "http://${aws_instance.cicd.public_ip}:9000"
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint — used in app configuration"
  value       = aws_db_instance.mysql.endpoint
}

output "s3_artifact_bucket" {
  description = "S3 bucket name for build artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vprofile_vpc.id
}
