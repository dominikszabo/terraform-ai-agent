data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "app" {
  name = "app-instance-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "app" {
  name = "app-instance-policy-${var.environment}"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "app-instance-profile-${var.environment}"
  role = aws_iam_role.app.name
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.bastion_sg_id]
  key_name               = var.key_name

  associate_public_ip_address = true

  tags = merge(var.tags, {
    Name        = "bastion-${var.environment}"
    Environment = var.environment
  })
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-${var.environment}-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name        = "app-${var.environment}"
      Environment = var.environment
    })
  }
}

resource "aws_autoscaling_group" "app" {
  name_prefix        = "app-asg-${var.environment}-"
  vpc_zone_identifier = var.subnet_ids
  min_size           = var.min_size
  max_size           = var.max_size
  desired_capacity   = var.desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value              = "app-${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value              = var.environment
    propagate_at_launch = true
  }
}
