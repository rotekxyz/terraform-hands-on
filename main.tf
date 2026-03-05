# ------------------------------------------------------------
# Terraform / AWS Provider
# ------------------------------------------------------------
# 利用するAWS providerのバージョンを定義
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 作成先リージョンの指定
provider "aws" {
  region = "us-west-2"
}

# ------------------------------------------------------------
# Network
# ------------------------------------------------------------

# VPC
# 本ハンズオン用のCIDRを定義
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Public Subnet
# EC2起動時にパブリックIPを自動付与する設定
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a"
}

# Internet Gateway
# VPCをインターネットに接続するためのゲートウェイ
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Route Table
# サブネットの通信経路を定義するルートテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

# デフォルトルート
# インターネット向け通信をIGWへルーティングする設定
resource "aws_route" "default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# SubnetとRouteTableを関連付ける設定
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------
# Security
# ------------------------------------------------------------

# EC2用セキュリティグループ
# SSHは使わず Session Managerで接続するため
# ingressルールは定義しない
resource "aws_security_group" "instance" {
  name   = "tf-demo-instance-sg"
  vpc_id = aws_vpc.main.id

  # Session Manager用の外向き通信のみ許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------
# IAM (Session Manager)
# ------------------------------------------------------------

# EC2がSSMを利用するためのIAMロールとインスタンスプロファイルの定義
resource "aws_iam_role" "ssm" {
  name = "tf-demo-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

# SSM用ポリシーをロールに付与
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2にアタッチするインスタンスプロファイル
resource "aws_iam_instance_profile" "ssm" {
  name = "tf-demo-ssm-profile"
  role = aws_iam_role.ssm.name
}

# ------------------------------------------------------------
# Compute
# ------------------------------------------------------------

# 使用するAMIの定義
# 最新のAmazon Linux 2023 AMIを取得
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# EC2インスタンスの定義
# Session Managerで接続するためSSHキーは不要
resource "aws_instance" "instance" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
}

# ------------------------------------------------------------
# Output
# ------------------------------------------------------------

# 作成されたEC2インスタンスID
# Session Manager接続時の確認に利用
output "instance_id" {
  value = aws_instance.instance.id
}
