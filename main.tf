# VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "my-${var.name_prefix}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "my-igw"
  }
}

# Public subnets
resource "aws_subnet" "public" {
  count = 3

  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  vpc_id            = aws_vpc.vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "my-${var.name_prefix}-public-subnet-${count.index + 1}"
  }
}

resource "aws_db_subnet_group" "private_group" {
  name       = "private_group"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id, aws_subnet.private[2].id]

  tags = {
    Name = "Private subnet group"
  }
}

# Private subnets
resource "aws_subnet" "private" {
  count = 3

  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index + 11)
  vpc_id            = aws_vpc.vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "my-${var.name_prefix}-private-subnet-${count.index + 1}"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "my-${var.name_prefix}-public-rt"
  }
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "my-${var.name_prefix}-private-rt"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "application" {
  name        = "application"
  description = "Security group for the Webapp application"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.security_cidr]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.security_cidr]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.security_cidr]
  }
  ingress {
    from_port   = 9234
    to_port     = 9234
    protocol    = "tcp"
    cidr_blocks = [var.security_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.security_cidr]
  }

  tags = {
    Name = "application"
  }
}

resource "aws_security_group" "database" {
  name        = "database"
  description = "Security group for the database"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.security_cidr]
  }

  tags = {
    Name = "database"
  }
}

resource "random_pet" "rg" {
  keepers = {
    # Generate a new pet name each time we switch to a new profile
    random_name = var.aws_profile
  }
}


resource "aws_s3_bucket" "s3b" {
  bucket        = random_pet.rg.id
  force_destroy = true
  tags = {
    Name = "${random_pet.rg.id}"
  }
}
resource "aws_s3_bucket_acl" "s3b_acl" {
  bucket = aws_s3_bucket.s3b.id
  acl    = "private"
}
resource "aws_s3_bucket_lifecycle_configuration" "s3b_lifecycle" {
  bucket = aws_s3_bucket.s3b.id
  rule {
    id     = "rule-1"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3b_encryption" {
  bucket = aws_s3_bucket.s3b.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

}
resource "aws_s3_bucket_public_access_block" "s3_block" {
  bucket              = aws_s3_bucket.s3b.id
  block_public_acls   = true
  block_public_policy = true
}

resource "aws_db_parameter_group" "postgres_11" {
  name   = "rds-pg-${var.name_prefix}"
  family = "postgres${var.db_version}"
  parameter {
    apply_method = "immediate"
    name         = "lc_messages"
    value        = "en_US.UTF-8"
  }
  parameter {
    apply_method = "immediate"
    name         = "lc_monetary"
    value        = "en_US.UTF-8"
  }
  parameter {
    apply_method = "immediate"
    name         = "lc_numeric"
    value        = "en_US.UTF-8"
  }
  parameter {
    apply_method = "immediate"
    name         = "lc_time"
    value        = "en_US.UTF-8"
  }
  parameter {
    apply_method = "immediate"
    name         = "autovacuum"
    value        = "1"
  }

}

resource "aws_iam_policy" "policy" {
  name        = "WebAppS3"
  description = "policy for s3"

  policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Action" : ["s3:DeleteObject", "s3:PutObject", "s3:GetObject", "s3:ListAllMyBuckets"]
        "Effect" : "Allow"
        "Resource" : ["arn:aws:s3:::${aws_s3_bucket.s3b.bucket}", "arn:aws:s3:::${aws_s3_bucket.s3b.bucket}/*"]
      }
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name = "EC2-CSYE6225"
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
}

resource "aws_iam_role_policy_attachment" "webapps3_policy_attachment" {
  policy_arn = aws_iam_policy.policy.arn
  role       = aws_iam_role.ec2_role.name
}

resource "aws_db_instance" "mydb" {
  allocated_storage      = var.db_storage
  engine                 = var.db_engine
  engine_version         = var.db_version
  instance_class         = var.db_instance_class
  multi_az               = false
  identifier             = var.db_identifier
  username               = var.db_username
  password               = var.db_password
  db_name                = var.db_name
  port                   = var.db_port
  publicly_accessible    = false
  skip_final_snapshot    = true
  vpc_security_group_ids = ["${aws_security_group.database.id}"]
  db_subnet_group_name   = aws_db_subnet_group.private_group.name
  parameter_group_name   = aws_db_parameter_group.postgres_11.name
}

resource "aws_iam_instance_profile" "iam_profile" {
  name = "iam_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "template_ami" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[1].id
  key_name                    = var.key_name
  associate_public_ip_address = true
  disable_api_termination     = false
  iam_instance_profile        = aws_iam_instance_profile.iam_profile.name

  vpc_security_group_ids = [
    aws_security_group.application.id
  ]
  root_block_device {
    delete_on_termination = true
    volume_size           = 50
    volume_type           = "gp2"
  }

  user_data = <<EOF
#!/bin/bash
cd /home/ec2-user || return
touch custom.properties
echo "aws.region=${var.aws_region}" >> custom.properties
echo "aws.s3.bucket=${aws_s3_bucket.s3b.bucket}" >> custom.properties

echo "spring.datasource.driver-class-name=org.postgresql.Driver" >> custom.properties
echo "spring.datasource.url=jdbc:postgresql://${aws_db_instance.mydb.endpoint}/${aws_db_instance.mydb.db_name}" >> custom.properties
echo "spring.datasource.username=${aws_db_instance.mydb.username}" >> custom.properties
echo "spring.datasource.password=${aws_db_instance.mydb.password}" >> custom.properties

echo "spring.datasource.dbcp2.test-while-idle=true" >> custom.properties
echo "spring.jpa.hibernate.ddl-auto=update" >> custom.properties
echo "spring.main.allow-circular-references=true" >> custom.properties
echo "server.port=9234" >> custom.properties
  EOF

  tags = {
    Name = "webapp_service"
  }

}

output "ec2instance" {
  value = aws_instance.template_ami.id
}

# Data Sources
data "aws_availability_zones" "available" {}

