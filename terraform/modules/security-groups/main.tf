resource "aws_security_group" "dev_ec2" {
  name        = "${var.project_name}-${var.environment}-app-ec2-sg"
  description = "Security group for Dev EC2 instance (SSH, HTTP, HTTPS, API)"
  vpc_id      = var.vpc_id

  # 1. SSH 접속 (포트 22)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # 2. HTTP 웹 접속 (포트 80)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 3. HTTPS 보안 웹 접속 (포트 443)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 4. 백엔드 REST API (포트 8080)
  ingress {
    description = "Backend API"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 5. 프론트엔드 Next.js 앱 (포트 3000)
  ingress {
    description = "Frontend Next.js"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 6. 모든 아웃바운드 인터넷 트래픽 허용
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-app-ec2-sg"
    }
  )
}
