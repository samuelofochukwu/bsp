resource "aws_s3_bucket" "site_origin" {
  bucket = "site-origin-elsampee"
  tags = {
    environment = "Labs"
  }
}

#To secure our bucket

resource "aws_s3_bucket_public_access_block" "site_origin" {
  bucket                  = aws_s3_bucket.site_origin.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site_origin" {
  bucket = aws_s3_bucket.site_origin.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "site_origin" {
  bucket = aws_s3_bucket.site_origin.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

#To upload a file to the bucket

resource "aws_s3_object" "content" {
  depends_on = [
    aws_s3_bucket.site_origin
  ]
  bucket                 = aws_s3_bucket.site_origin.bucket
  key                    = "index.html" #Lets you specify the name of the resource once its uploaded to the bucket
  source                 = "./index.html"
  server_side_encryption = "AES256"
  content_type           = "text/html" #Lets you specify the type of file you are uploading and will allow you to view it in the browser instead of downloading it.
}

#To create a cloudfront distribution
#Cloudfront origin access control is part of the distribution and is used to restrict access to the bucket. Distribution is dependent on it.
resource "aws_cloudfront_origin_access_control" "site_access" {
  name                              = "cloudfront-access-to-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site_access" {
  depends_on = [
    aws_s3_bucket.site_origin,
    aws_cloudfront_origin_access_control.site_access
  ]

  enabled             = true         #This will enable the distribution upon creation
  default_root_object = "index.html" #This will allow you to access the index.html file without having to specify it in the url

  origin {
    domain_name              = aws_s3_bucket.site_origin.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site_origin.id
    origin_access_control_id = aws_cloudfront_origin_access_control.site_access.id
  }

  is_ipv6_enabled = true
  default_cache_behavior { #describes how we want cloudfront to fetch and cache content from our origin
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site_origin.id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "https-only" #This will force cloudfront to only accept https requests
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true #This will allow us to use the default cloudfront certificate since we are not using a custom domain
  }
  tags = {
    environment = "Labs"
  }
}
#IAM policy that allows cloudfront to access the bucket

resource "aws_s3_bucket_policy" "site_origin" {
  depends_on = [
    data.aws_iam_policy_document.site_origin
  ]
  bucket = aws_s3_bucket.site_origin.id
  policy = data.aws_iam_policy_document.site_origin.json
}

data "aws_iam_policy_document" "site_origin" {
  depends_on = [
    aws_cloudfront_distribution.site_access,
    aws_s3_bucket.site_origin
  ]
  statement {
    sid    = "s3_cloudfront_static_website_access"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    principals {
      type = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.site_origin.bucket}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      
      values = [aws_cloudfront_distribution.site_access.arn]
    }
  }
}
