# ============================================================
# outputs.tf — Consolidated Outputs
# ============================================================

output "all_in_one_public_ip" {
  description = "Public IP of the all-in-one server"
  value       = aws_instance.all_in_one.public_ip
}

output "all_in_one_private_ip" {
  description = "Private IP of the all-in-one server"
  value       = aws_instance.all_in_one.private_ip
}

output "jenkins_url" {
  description = "Jenkins UI URL"
  value       = "http://${aws_instance.all_in_one.public_ip}:8080"
}

output "nexus_url" {
  description = "Nexus Repository Manager URL"
  value       = "http://${aws_instance.all_in_one.public_ip}:8081"
}

output "sonarqube_url" {
  description = "SonarQube UI URL"
  value       = "http://${aws_instance.all_in_one.public_ip}:9000"
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.mysql.endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vprofile_vpc.id
}