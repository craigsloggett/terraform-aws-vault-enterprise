data "aws_iam_role" "kms_additional_usage" {
  count = var.kms_key.additional_usage_role_name != null ? 1 : 0

  name = var.kms_key.additional_usage_role_name
}

data "aws_iam_policy_document" "auto_unseal_key_policy" {
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"

    # Administrative actions only, no cryptographic operations. Keeping
    # kms:Put* delegated to IAM lets the deployer correct this policy,
    # preventing lockout, while usage stays pinned to the principals
    # listed in the AutoUnsealUsage statement below.
    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
    ]

    resources = ["*"] # The key this policy is attached to, not all keys.

    # https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html
    # A principal in arn:aws:iam::111122223333:root" format does not represent
    # the AWS account root user, despite the use of "root" in the account
    # identifier.
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AutoUnsealUsage"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = concat(
        [aws_iam_role.vault_enterprise.arn],
        data.aws_iam_role.kms_additional_usage[*].arn
      )
    }
  }
}

resource "aws_kms_key" "auto_unseal" {
  description             = "Vault Enterprise Auto-unseal Key"
  deletion_window_in_days = var.kms_key.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.auto_unseal_key_policy.json

  tags = {
    Name = var.kms_key.name
  }
}

resource "aws_kms_alias" "auto_unseal" {
  name          = "alias/${var.kms_key.alias}"
  target_key_id = aws_kms_key.auto_unseal.key_id
}
