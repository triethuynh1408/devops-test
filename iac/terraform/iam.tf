resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

data "aws_iam_policy_document" "oidc_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-gha-oidc-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume.json
}

data "aws_iam_policy_document" "gha_policy" {

  # ECR push/pull
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages"
    ]
    resources = [
      aws_ecr_repository.app.arn,
      "${aws_ecr_repository.app.arn}/*"
    ]
  }

  # Required for STS identity
  statement {
    effect = "Allow"
    actions = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Allow EKS access
  statement {
    effect = "Allow"
    actions = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha" {
  name   = "${var.project_name}-gha-policy"
  policy = data.aws_iam_policy_document.gha_policy.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.gha.arn
}
