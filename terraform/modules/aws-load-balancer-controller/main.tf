data "aws_partition" "current" {}

# LBC 컨트롤러 파드가 Assume할 IAM 역할의 신뢰 정책 (OIDC IRSA)
data "aws_iam_policy_document" "controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# AWS Load Balancer Controller 파드가 사용할 IAM Role
resource "aws_iam_role" "controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.controller_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-aws-load-balancer-controller"
    }
  )
}

# AWS Load Balancer Controller 공식 IAM Policy (ELBv2, EC2, WAF, ACM 등 관리 권한)
resource "aws_iam_policy" "controller" {
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM Policy for AWS Load Balancer Controller in EKS cluster ${var.cluster_name}"
  policy      = file("${path.module}/iam_policy.json")

  tags = var.tags
}

# IAM Role에 Policy 연결
resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}
