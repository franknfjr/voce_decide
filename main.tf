# Configure o provider AWS
provider "aws" {
  region = "us-east-1"  # Ajuste para sua região preferida
}

# VPC e configurações de rede
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "elixir-app-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "elixir-app-subnet"
  }
}

# Security Group para a instância EC2
resource "aws_security_group" "elixir_app" {
  name        = "elixir-app-sg"
  description = "Security group for Elixir application"
  vpc_id      = aws_vpc.main.id

  # Permitir tráfego HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir tráfego HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir tráfego SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir tráfego Phoenix (porta 4000)
  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elixir-app-sg"
  }
}

# Instância EC2
resource "aws_instance" "elixir_app" {
  ami           = "ami-0440d3b780d96b29d"  # Ubuntu 22.04 LTS (ajuste conforme necessário)
  instance_type = "t2.micro"  # Ajuste conforme necessidade da aplicação

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.elixir_app.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20  # Tamanho em GB
    volume_type = "gp2"
  }

  tags = {
    Name = "elixir-app-server"
  }
}

# Bucket S3
resource "aws_s3_bucket" "app_storage" {
  bucket = "elixir-app-storage-${random_id.bucket_suffix.hex}"
}

# Sufixo aleatório para o nome do bucket S3
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Configuração de criptografia para o bucket S3
resource "aws_s3_bucket_server_side_encryption_configuration" "app_storage" {
  bucket = aws_s3_bucket.app_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role para a instância EC2 acessar o S3
resource "aws_iam_role" "ec2_s3_access" {
  name = "ec2-s3-access-role"

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

# IAM Policy para acesso ao S3
resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3-access-policy"
  role = aws_iam_role.ec2_s3_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.app_storage.arn,
          "${aws_s3_bucket.app_storage.arn}/*"
        ]
      }
    ]
  })
}

# Perfil de instância para anexar a role à EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-s3-profile"
  role = aws_iam_role.ec2_s3_access.name
}

# Outputs úteis
output "ec2_public_ip" {
  value = aws_instance.elixir_app.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_storage.id
}
