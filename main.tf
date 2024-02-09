provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "ntrancrc"
}

resource "aws_cloudfront_distribution" "my_distribution" {
  aliases             = ["ntransw.com"]
  default_root_object = "index.html"
  tags                = {}
  web_acl_id          = "arn:aws:wafv2:us-east-1:730335278778:global/webacl/CreatedByCloudFront-01a802a5-ae22-4596-8b76-f97c46cf9e4e/df641815-01c3-4882-804e-6f243136096c"

  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.my_bucket.bucket_regional_domain_name
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    viewer_protocol_policy = "allow-all"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn             = "arn:aws:acm:us-east-1:730335278778:certificate/0a61bcb0-cc0b-4524-9162-6d8ee50c14ee"
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
}

resource "aws_route53_zone" "main" {
  name = "ntransw.com"
}

resource "aws_dynamodb_table" "my_table" {
  name                        = "cloudresumedb"
  deletion_protection_enabled = true
  billing_mode                = "PAY_PER_REQUEST"

  attribute {
      name = "webdata"
      type = "S"
  }

  attribute {
    name = "viewcounter"
    type = "N"
  }

  global_secondary_index {
      hash_key           = "viewcounter"
      name               = "viewcounter-index"
      non_key_attributes = []
      projection_type    = "ALL"
      read_capacity      = 0
      write_capacity     = 0
  }
}

resource "aws_lambda_function" "my_function" {
  role          = "arn:aws:iam::730335278778:role/service-role/DBAccess"
  filename      = "./increment_viewcount.zip"
  function_name = "arn:aws:lambda:us-east-1:730335278778:function:increment_viewcount"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  source_code_hash = filebase64sha256("./increment_viewcount.zip")
}

resource "aws_apigatewayv2_api" "my_http_api" {
  description   = "Increments and outputs view counter"
  name          = "increment_viewcount_API"
  protocol_type = "HTTP"
  tags          = {}

  cors_configuration {
      allow_credentials = false
      allow_headers     = []
      allow_methods     = []
      allow_origins     = ["*"]
      expose_headers    = []
      max_age           = 0
  }
}

resource "aws_apigatewayv2_integration" "my_integration" {
  api_id           = aws_apigatewayv2_api.my_http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = "arn:aws:lambda:us-east-1:730335278778:function:increment_viewcount"
}

data "aws_iam_policy_document" "lambda_execution_policy" {
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.my_table.arn]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:CreateLogGroup", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "DBAccess"
  path               = "/service-role/"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}
