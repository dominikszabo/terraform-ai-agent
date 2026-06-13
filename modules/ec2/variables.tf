variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for app servers"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs for bastion"
}

variable "bastion_sg_id" {
  type        = string
  description = "Security group ID for bastion"
}

variable "app_sg_id" {
  type        = string
  description = "Security group ID for app servers"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "bastion_instance_type" {
  type        = string
  description = "Bastion instance type"
  default     = "t3.nano"
}

variable "key_name" {
  type        = string
  description = "SSH key pair name"
  default     = null
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "min_size" {
  type        = number
  description = "Minimum number of app instances"
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Maximum number of app instances"
  default     = 3
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of app instances"
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
