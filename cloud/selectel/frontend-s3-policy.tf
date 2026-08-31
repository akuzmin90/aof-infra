locals {
  frontend_s3_bucket_policies = {
    for instance, bucket in local.frontend_bucket_names : instance => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AllowPublicFrontendRead"
          Effect    = "Allow"
          Principal = "*"
          Action = [
            "s3:GetObject"
          ]
          Resource = "arn:aws:s3:::${bucket}/*"
        },
        {
          Sid    = "AllowFrontendPublisherBucketAccess"
          Effect = "Allow"
          Principal = {
            AWS = [
              var.frontend_s3_publisher_user_id,
              var.frontend_s3_policy_manager_user_id
            ]
          }
          Action = [
            "s3:GetBucketLocation",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads"
          ]
          Resource = "arn:aws:s3:::${bucket}"
        },
        {
          Sid    = "AllowFrontendPublisherObjectAccess"
          Effect = "Allow"
          Principal = {
            AWS = [
              var.frontend_s3_publisher_user_id,
              var.frontend_s3_policy_manager_user_id
            ]
          }
          Action = [
            "s3:AbortMultipartUpload",
            "s3:DeleteObject",
            "s3:GetObject",
            "s3:ListMultipartUploadParts",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::${bucket}/*"
        }
      ]
    })
  }
}

resource "aws_s3_bucket_policy" "frontend_instance" {
  for_each = local.frontend_s3_bucket_policies

  bucket = openstack_objectstorage_container_v1.frontend_instance[each.key].name
  policy = each.value
  region = "ru-7"
}
