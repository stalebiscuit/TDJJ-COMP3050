terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "dockerhub_username" {
  description = "Docker Hub username (used in UserData to pull images)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "Instance type must be t3.micro or t3.small."
  }
}

variable "ssh_location" {
  description = "CIDR block allowed to SSH into the instance"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_location, 0))
    error_message = "ssh_location must be a valid CIDR block (e.g. 0.0.0.0/0 or 203.0.113.0/24)."
  }
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.tutorial.id]
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    exec > /var/log/user-data.log 2>&1
    set -ex
    dnf update -y
    dnf install -y docker
    systemctl start docker
    systemctl enable docker
    docker pull ${var.dockerhub_username}/comp3050-project:latest
    docker stop comp3050-server 2>/dev/null || true
    docker rm comp3050-server 2>/dev/null || true
    docker run -d --name comp3050-server --restart unless-stopped \
      -p 8000:8000 \
      -e APP_USER=admin \
      -e APP_PASS=secret123 \
      ${var.dockerhub_username}/comp3050-project:latest
  EOF

  tags = {
    Name = "COMP3050-P"
  }
}

resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.server.id

  tags = {
    Name = "Project-CICD-EIP"
  }
}

output "elastic_ip" {
  description = "Elastic IP address (stable — does not change)"
  value       = aws_eip.app.public_ip
}

output "instance_public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.server.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.server.id
}

output "info_test_url" {
  description = "Challenge 3.2 — open in a browser after apply"
  value       = "http://${aws_eip.app.public_ip}:8000/info?y=0&x=0"
}

resource "aws_security_group" "tutorial" {
  name        = "terraform-tutorial-sg"
  description = "SSH, HTTP, HTTPS, and game server (Week 7)"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_location]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Game server"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
