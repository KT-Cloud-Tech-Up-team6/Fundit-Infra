# 1. EC2 인스턴스 생성
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-app-root-ebs"
      }
    )
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-app-ec2"
    }
  )
}

# 2. 탄력적 IP (EIP) 생성 및 EC2 연결 (서버 재부팅해도 IP 안 바뀜!)
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-app-eip"
    }
  )
}
