terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

resource "aws_security_group" "jira" {
  name        = "${var.name_prefix}-jira-sg"
  description = "Security group for Jira demo node"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-jira-sg"
  })
}

resource "aws_iam_role" "jira" {
  name               = "${var.name_prefix}-jira-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jira.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jira" {
  name = "${var.name_prefix}-jira-profile"
  role = aws_iam_role.jira.name
}

resource "aws_instance" "jira" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  associate_public_ip_address = false
  iam_instance_profile   = aws_iam_instance_profile.jira.name
  vpc_security_group_ids = [aws_security_group.jira.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    ansible_user = var.ansible_user
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-jira"
  })
}

resource "aws_eip_association" "jira" {
  allocation_id = var.eip_allocation_id
  instance_id   = aws_instance.jira.id
}

output "jira_instance_id" {
  value = aws_instance.jira.id
}

output "jira_private_ip" {
  value = aws_instance.jira.private_ip
}

output "jira_public_ip" {
  value = aws_eip_association.jira.public_ip
}

output "ansible_inventory" {
  description = "INI formatted single-host inventory for Ansible"
  value       = <<EOT
[jira]
${aws_instance.jira.id} ansible_connection=amazon.aws.aws_ssm ansible_user=${var.ansible_user} ansible_aws_ssm_region=${var.region}
EOT
}
