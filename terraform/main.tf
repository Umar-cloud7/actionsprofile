# ============================================================
# main.tf — Consolidated VProfile Project (Single Instance)
# ============================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket = "artifacts-umar"
    key    = "vprofile/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" { region = var.aws_region }

# --- Security Group ---
resource "aws_security_group" "all_in_one_sg" {
  name        = "${var.project_name}-all-in-one-sg"
  description = "Access for Web, App, and CI/CD tools"
  vpc_id      = aws_vpc.vprofile_vpc.id

  # HTTP
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  # Jenkins
  ingress { from_port = 8080; to_port = 8080; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  # Nexus
  ingress { from_port = 8081; to_port = 8081; protocol = "tcp"; cidr_blocks = [var.your_ip] }
  # SonarQube
  ingress { from_port = 9000; to_port = 9000; protocol = "tcp"; cidr_blocks = [var.your_ip] }
  # SSH
  ingress { from_port = 22; to_port = 22; protocol = "tcp"; cidr_blocks = [var.your_ip] }

  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# --- Key Pair ---
resource "aws_key_pair" "vprofile_key" {
  key_name   = "vprofile-key"
  public_key = file(var.public_key)
}

# --- EC2 Instance ---
resource "aws_instance" "all_in_one" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.all_in_one_sg.id]
  key_name               = aws_key_pair.vprofile_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(file("${path.module}/scripts/setup_all.sh"))

  root_block_device {
    volume_size           = 40
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.project_name}-all-in-one" }
}

# --- RDS Database ---
resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  db_name                = var.db_name
  engine                 = "mysql"
  instance_class         = var.db_instance_class
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.all_in_one_sg.id] # Points to new SG
}

# --- CloudWatch Alarm ---
resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Monitor CPU usage"
  dimensions = {
    InstanceId = aws_instance.all_in_one.id # Pointing to new instance
  }
}