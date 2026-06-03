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

variable "jaydenn6" {
  description = "Docker Hub username (used in UserData to pull images)"
  type        = string
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = "t3.micro"
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.tutorial.id]
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker git
    systemctl start docker
    systemctl enable docker
    git clone https://github.com/jaydennguyen296/TDJJ-COMP3050.git /opt/comp3050
    cd /opt/comp3050
    docker build -t comp3050-server .
    docker run -d --name comp3050-server --restart unless-stopped \
      -p 80:8000 \
      -e APP_USER=admin \
      -e APP_PASS=secret123 \
      comp3050-server
  EOF

  tags = {
    Name = "COMP3050-P"
  }
}

resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

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
  value       = aws_instance.tutorial.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

resource "aws_security_group" "tutorial" {
  name        = "terraform-tutorial-sg"
  description = "Allow SSH and HTTP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
