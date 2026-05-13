# ============================================================
# main.tf — VProfile Project Infrastructure
# Author: Umar Farooque Shaikh
# Stack: Nginx + Tomcat + MySQL + Nexus + SonarQube on AWS
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"

  # Remote state storage — keeps your state safe in S3
  backend "s3" {
    bucket = "artifacts-umar"
    key    = "vprofile/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# DATA SOURCES
# ============================================================

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Available AZs in chosen region
data "aws_availability_zones" "available" {
  state = "available"
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "vprofile_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ============================================================
# SUBNETS
# ============================================================

# Public Subnets — for Nginx (Load Balancer / Web tier)
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.vprofile_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Private Subnets — for Tomcat App + MySQL DB
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.vprofile_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ============================================================
# INTERNET GATEWAY + NAT GATEWAY
# ============================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vprofile_vpc.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-nat-eip"
    Project = var.project_name
  }
}

# NAT Gateway — allows private subnets to reach internet (for updates/pulls)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name    = "${var.project_name}-nat"
    Project = var.project_name
  }

  depends_on = [aws_internet_gateway.igw]
}

# ============================================================
# ROUTE TABLES
# ============================================================

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vprofile_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table — routes through NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vprofile_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name    = "${var.project_name}-private-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ============================================================
# SECURITY GROUPS
# ============================================================

# ALB Security Group — accepts HTTP/HTTPS from internet
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP/HTTPS inbound to ALB"
  vpc_id      = aws_vpc.vprofile_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

# Nginx (Web tier) Security Group — accepts traffic only from ALB
resource "aws_security_group" "nginx_sg" {
  name        = "${var.project_name}-nginx-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_vpc.vprofile_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description     = "HTTP from ALB only"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "SSH from your IP only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-nginx-sg"
    Project = var.project_name
  }
}

# Tomcat (App tier) Security Group — accepts traffic only from Nginx
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Allow traffic from Nginx only"
  vpc_id      = aws_vpc.vprofile_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx_sg.id]
    description     = "Tomcat from Nginx only"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "SSH from your IP only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}

# MySQL (DB tier) Security Group — accepts traffic only from App tier
resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Allow MySQL from App tier only"
  vpc_id      = aws_vpc.vprofile_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
    description     = "MySQL from App tier only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-db-sg"
    Project = var.project_name
  }
}

# CI/CD Tools Security Group — Jenkins, Nexus, SonarQube
resource "aws_security_group" "cicd_sg" {
  name        = "${var.project_name}-cicd-sg"
  description = "Allow access to CI/CD tools"
  vpc_id      = aws_vpc.vprofile_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "Jenkins UI"
  }

  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "Nexus UI"
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "SonarQube UI"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "SSH from your IP only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-cicd-sg"
    Project = var.project_name
  }
}

# ============================================================
# KEY PAIR
# ============================================================

resource "aws_key_pair" "vprofile_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# EC2 INSTANCES
# ============================================================

# Nginx Web Server — public subnet
resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.web_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]
  key_name               = aws_key_pair.vprofile_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(templatefile("${path.module}/scripts/nginx_setup.sh", {
    app_private_ip = aws_instance.app.private_ip
  }))

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-nginx"
    Project     = var.project_name
    Environment = var.environment
    Role        = "web"
  }

  depends_on = [aws_instance.app]
}

# Tomcat App Server — private subnet
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.vprofile_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(templatefile("${path.module}/scripts/app_setup.sh", {
    db_endpoint = aws_db_instance.mysql.endpoint
    db_name     = var.db_name
    db_user     = var.db_username
    db_password = var.db_password
    nexus_url   = "http://${aws_instance.cicd.private_ip}:8081"
  }))

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-app"
    Project     = var.project_name
    Environment = var.environment
    Role        = "app"
  }

  depends_on = [aws_db_instance.mysql]
}

# CI/CD Server — Jenkins + Nexus + SonarQube (public subnet)
resource "aws_instance" "cicd" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.cicd_instance_type  # t3.medium minimum for Nexus+Sonar
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.cicd_sg.id]
  key_name               = aws_key_pair.vprofile_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(file("${path.module}/scripts/cicd_setup.sh"))

  root_block_device {
    volume_size           = 30   # Nexus needs more space for artifacts
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-cicd"
    Project     = var.project_name
    Environment = var.environment
    Role        = "cicd"
  }
}

# ============================================================
# RDS MYSQL — Multi-AZ for High Availability
# ============================================================

resource "aws_db_subnet_group" "mysql" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name    = "${var.project_name}-db-subnet-group"
    Project = var.project_name
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  # High Availability — Multi-AZ
  multi_az = true

  # Disaster Recovery — automated backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Prevent accidental deletion
  deletion_protection = false   # Set to true in production
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"

  tags = {
    Name        = "${var.project_name}-mysql"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ============================================================
# APPLICATION LOAD BALANCER
# ============================================================

resource "aws_lb" "vprofile_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "nginx_tg" {
  name     = "${var.project_name}-nginx-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vprofile_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = {
    Name    = "${var.project_name}-nginx-tg"
    Project = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "nginx" {
  target_group_arn = aws_lb_target_group.nginx_tg.arn
  target_id        = aws_instance.nginx.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.vprofile_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_tg.arn
  }
}

# ============================================================
# S3 BUCKET — Artifact Storage + State Backend
# ============================================================

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-umar-${var.environment}"

  tags = {
    Name        = "${var.project_name}-artifacts-umar"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# IAM — EC2 Instance Role (least privilege)
# ============================================================

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${var.project_name}-ec2-s3-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ============================================================
# CLOUDWATCH ALARMS
# ============================================================

resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "${var.project_name}-app-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "App server CPU above 80%"

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  alarm_name          = "${var.project_name}-db-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "RDS connections above 100"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mysql.id
  }

  tags = {
    Project = var.project_name
  }
}
