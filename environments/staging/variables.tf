variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "target_account_id" {
  type    = string
  default = "074642417664"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "key_name" {
  type    = string
  default = "AWS-SSH"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  sensitive = true
}

variable "db_password" {
  type    = string
  sensitive = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "multi_az" {
  type    = bool
  default = true
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

variable "desired_capacity" {
  type    = number
  default = 2
}
