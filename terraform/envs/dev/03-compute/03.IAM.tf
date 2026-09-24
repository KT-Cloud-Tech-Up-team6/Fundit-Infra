# ====================================================
# Ansible 보안 점검 서버 전용 IAM Role 및 정책 (이슈 #114)
# ====================================================

# 1. EC2 인스턴스 Assume Role
resource "aws_iam_role" "ansible_inspector" {
  name = "${var.project_name}-${var.environment}-ansible-inspector-role"

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
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-ansible-inspector-role"
    }
  )
}

# 2. EC2 인스턴스 프로파일
resource "aws_iam_instance_profile" "ansible_inspector" {
  name = "${var.project_name}-${var.environment}-ansible-inspector-profile"
  role = aws_iam_role.ansible_inspector.name

  tags = var.common_tags
}

# 3. AWS 관리형 정책: SecurityAudit (보안 설정 읽기/조회)
resource "aws_iam_role_policy_attachment" "inspector_security_audit" {
  role       = aws_iam_role.ansible_inspector.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/SecurityAudit"
}

# 4. AWS 관리형 정책: AmazonSSMManagedInstanceCore (점검 서버 자체의 SSM 관리 등록용)
resource "aws_iam_role_policy_attachment" "inspector_ssm_managed" {
  role       = aws_iam_role.ansible_inspector.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 5. EKS 워커 노드 대상 SSM Session Manager 시작 및 세션 제어 정책
resource "aws_iam_role_policy" "inspector_ssm_session" {
  name = "${var.project_name}-${var.environment}-inspector-ssm-session-policy"
  role = aws_iam_role.ansible_inspector.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # (1) 대상 인스턴스 및 SSM 상태 조회 권한
      {
        Sid    = "SSMAndEC2Discovery"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:DescribeInstanceInformation",
          "ssm:GetConnectionStatus"
        ]
        Resource = "*"
      },
      # (2) fundit-dev-eks 클러스터 노드로만 SSM Session 시작 제한
      {
        Sid    = "StartSessionForEKSNodesOnly"
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/fundit-dev-eks" = "owned"
          }
        }
      },
      # (3) 기본 세션 문서(Shell) 실행 권한
      {
        Sid    = "StartSessionDocument"
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::document/SSM-SessionManagerRunShell",
          "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::document/AWS-StartInteractiveCommand"
        ]
      },
      # (4) 세션 종료 및 재개는 점검 서버에서 생성한 세션에 한정 (i-0f0f2c3d098d27291- 접두어)
      {
        Sid    = "ManageOwnSSMSessions"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:session/${module.ec2.instance_id}-*"
        ]
      }
    ]
  })
}

# 6. Ansible 파일 전송용 전용 S3 버킷 접근 권한 정책
resource "aws_iam_role_policy" "inspector_s3_transfer" {
  name = "${var.project_name}-${var.environment}-inspector-s3-policy"
  role = aws_iam_role.ansible_inspector.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AnsibleTransferBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::fundit-security-ansible-transfer-dev-team6"
      },
      {
        Sid    = "AnsibleTransferObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::fundit-security-ansible-transfer-dev-team6/*"
      }
    ]
  })
}
