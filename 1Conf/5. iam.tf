// trusts the EC2 role from the other account + grants ACM permissions //

resource "aws_iam_role" "acm_cross_account_role" {
  name = "bp-acm-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = [
            "arn:aws:iam::654654447396:role/CAN1-ec2-acm-role",
            "arn:aws:iam::654654447396:role/CAN2-ec2-acm-role",
            "arn:aws:iam::767397721654:role/US1-ec2-acm-role",
            "arn:aws:iam::767397721654:role/US2-ec2-acm-role",
            "arn:aws:iam::465881973817:role/USUAT-ec2-acm-role",
            "arn:aws:iam::912818724188:role/CAUAT-ec2-acm-role"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "acm_policy" {
  name = "bp-acm-policy"
  role = aws_iam_role.acm_cross_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "acm:GetCertificate",
          "acm:ExportCertificate",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      }
    ]
  })
}