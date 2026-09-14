# CNPG가 관리하는 PostgreSQL Cluster의 ServiceAccount가 assume하는 역할.
# CNPG는 Cluster와 같은 이름의 ServiceAccount를 자동 생성하므로 sub 조건을 정확히 고정한다.
# dev 네임스페이스는 ArgoCD AppProject의 namespaceResourceWhitelist가 전부 열려 있어
# 와일드카드를 쓰면 그 네임스페이스의 다른 워크로드도 이 Role을 assume할 수 있다.
data "aws_iam_policy_document" "backup_assume_role" {
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
      values   = ["system:serviceaccount:${var.backup_namespace}:${var.postgres_cluster_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "CNPGBackupRole-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "s3_backup" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.backup_bucket_name}"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.backup_bucket_name}/*"]
  }
}

resource "aws_iam_policy" "s3_backup" {
  name   = "CNPGBackupPolicy-${var.cluster_name}"
  policy = data.aws_iam_policy_document.s3_backup.json
}

resource "aws_iam_role_policy_attachment" "backup_s3" {
  role       = aws_iam_role.backup.name
  policy_arn = aws_iam_policy.s3_backup.arn
}
