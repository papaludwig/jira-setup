variable "region" {
  type        = string
  description = "AWS region to deploy into"
}

variable "vpc_id" {
  type        = string
  description = "VPC where the instance will live"
}

variable "subnet_id" {
  type        = string
  description = "Subnet for the Jira instance"
}

variable "eip_allocation_id" {
  type        = string
  description = "Elastic IP allocation ID to attach to the instance"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for Jira"
  default     = "m6i.xlarge"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the EC2 key pair to associate"
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB"
  default     = 100
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH to the instance"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for naming AWS resources"
  default     = "jira-demo"
}

variable "ansible_user" {
  type        = string
  description = "Username that Ansible will use for SSH"
  default     = "ansible"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default = {
    Project = "jira-demo"
  }
}
