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

output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.mysql.endpoint
}

