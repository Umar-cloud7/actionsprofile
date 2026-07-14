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

# --- VPC ---
resource "aws_vpc" "vprofile_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-vpc" }
}

# --- Subnets ---
data "aws_availability_zones" "available" {}
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.vprofile_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-subnet-${count.index}" }
}

# --- Security Group ---
resource "aws_security_group" "all_in_one_sg" {
  name        = "${var.project_name}-all-in-one-sg"
  vpc_id      = aws_vpc.vprofile_vpc.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8080; to_port = 8080; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8081; to_port = 8081; protocol = "tcp"; cidr_blocks = [var.your_ip] }
  ingress { from_port = 9000; to_port = 9000; protocol = "tcp"; cidr_blocks = [var.your_ip] }
  ingress { from_port = 22; to_port = 22; protocol = "tcp"; cidr_blocks = [var.your_ip] }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# --- IAM ---
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- EC2 Instance ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]n  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_key_pair" "vprofile_key" {
  key_name   = "vprofile-key"
  public_key = file(var.public_key)
}

resource "aws_instance" "all_in_one" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.all_in_one_sg.id]
  key_name               = aws_key_pair.vprofile_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Ensure these files exist in your repository at terraform/scripts/
  user_data = base64encode(join("\n", [
    file("${path.module}/scripts/app_setup.sh"),
    file("${path.module}/scripts/cicd_setup.sh"),
    file("${path.module}/scripts/nginx_setup.sh")
  ]))

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