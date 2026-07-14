# ============================================================
# variables.tf — All configurable inputs
# ============================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for all resource naming"
  type        = string
  default     = "vprofile"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ---- Network ----

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (Nginx/ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (App/DB)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "your_ip" {
  description = "Your public IP for SSH access — format: x.x.x.x/32"
  type        = string
  # Set this in terraform.tfvars — never hardcode your IP here
}

# ---- EC2 ----

variable "web_instance_type" {
  description = "Instance type for Nginx web server"
  type        = string
  default     = "t2.micro"
}

variable "app_instance_type" {
  description = "Instance type for Tomcat app server"
  type        = string
  default     = "t2.micro"
}

variable "cicd_instance_type" {
  description = "Instance type for Jenkins + Nexus + SonarQube (needs at least t3.medium)"
  type        = string
  default     = "t2.micro"
}

variable "public_key" {
  description = "Path to your SSH public key file"
  type        = string

}

# ---- RDS ----

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "MySQL database name"
  type        = string
  default     = "accounts"
}

variable "db_username" {
  description = "MySQL master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "MySQL master password — set in terraform.tfvars, never commit this"
  type        = string
  sensitive   = true
}
