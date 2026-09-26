# ----------------------------------------------------
# fck-nat ASG Self-Healing용 IAM 역할 및 인스턴스 프로파일
# 인스턴스 기동 시 사전 할당된 고정 ENI를 자동으로 Attach하기 위한 권한 부여
# ----------------------------------------------------

resource "aws_iam_role" "nat_instance" {
  name = "${var.project_name}-${var.environment}-nat-instance-role"

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

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-instance-role"
    }
  )
}

resource "aws_iam_policy" "nat_instance" {
  name        = "${var.project_name}-${var.environment}-nat-instance-policy"
  description = "IAM policy for fck-nat instance to attach static ENI and configure NAT"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2NetworkInterfaceManagement"
        Effect = "Allow"
        Action = [
          "ec2:AttachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-instance-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "nat_instance" {
  role       = aws_iam_role.nat_instance.name
  policy_arn = aws_iam_policy.nat_instance.arn
}

# SSH 키 없이도 AWS Systems Manager Session Manager로 접속/디버깅할 수 있도록 표준 정책 연결
resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  name = "${var.project_name}-${var.environment}-nat-instance-profile"
  role = aws_iam_role.nat_instance.name

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-instance-profile"
    }
  )
}
