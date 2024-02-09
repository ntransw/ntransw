provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "ntrancrc"
}

resource "aws_cloudfront_distribution" "my_distribution" {
  aliases             = ["ntransw.com"]
  default_root_object = "index.html"
  staging             = false
  retain_on_delete    = false
  price_class         = "PriceClass_All"
  http_version        = "http2"
  web_acl_id          = "arn:aws:wafv2:us-east-1:730335278778:global/webacl/CreatedByCloudFront-01a802a5-ae22-4596-8b76-f97c46cf9e4e/df641815-01c3-4882-804e-6f243136096c"
  wait_for_deployment = true
  enabled             = true
  is_ipv6_enabled     = true
  tags                = {}
  tags_all            = {}

  origin {
    domain_name         = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id           = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    connection_attempts = 3
    connection_timeout  = 10
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    viewer_protocol_policy = "allow-all"
    compress               = true
    default_ttl            = 0
    max_ttl                = 0
    min_ttl                = 0
    smooth_streaming       = false
    trusted_key_groups     = []
  }

  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn             = "arn:aws:acm:us-east-1:730335278778:certificate/0a61bcb0-cc0b-4524-9162-6d8ee50c14ee"
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

resource "aws_route53_zone" "main" {
  name          = "ntransw.com"
  comment       = "Managed by Terraform"
  force_destroy = false
  tags          = {}
  tags_all      = {}
}

resource "aws_dynamodb_table" "my_table" {
  name                        = "cloudresumedb"
  deletion_protection_enabled = true
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "webdata"
  read_capacity               = 0
  write_capacity              = 0
  stream_enabled              = false
  table_class                 = "STANDARD"
  tags                        = {}
  tags_all                    = {}

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

  point_in_time_recovery {
    enabled = false
  }
}

# Attempted to automatically create zip every time the SHA for the Python back-end changes,
# but it's not really working right now, so I'll leave it out. As a result, the zip must
# always be in infra/
#
# resource "null_resource" "create_zip" {
#     triggers = {
#         files = filesha256("../backend/lambda_function.py")
#     }

#     provisioner "local-exec" {
#         command = "zip increment_viewcount.zip ../backend/lambda_function.py"
#     }
# }

data "archive_file" "lambda_zip" {
    type        = "zip"
    source_dir  = "../backend"
    output_path = "./increment_viewcount.zip"
}

resource "aws_lambda_function" "my_function" {
  role                           = "arn:aws:iam::730335278778:role/service-role/DBAccess"
  filename                       = data.archive_file.lambda_zip.output_path
  function_name                  = "arn:aws:lambda:us-east-1:730335278778:function:increment_viewcount"
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.12"
  source_code_hash               = filebase64sha256("./increment_viewcount.zip")
  architectures                  = ["arm64"]
  layers                         = []
  memory_size                    = 128
  package_type                   = "Zip"
  publish                        = false
  reserved_concurrent_executions = -1
  skip_destroy                   = false
  timeout                        = 3
  tags                           = {}
  tags_all                       = {}


  ephemeral_storage {
    size = 512
  }

  logging_config {
    log_format = "Text"
    log_group  = "/aws/lambda/increment_viewcount"
  }

  tracing_config {
    mode = "PassThrough"
  }
}

resource "aws_apigatewayv2_api" "my_http_api" {
  api_key_selection_expression = "$request.header.x-api-key"
  description                  = "Increments and outputs view counter"
  name                         = "increment_viewcount_API"
  route_selection_expression   = "$request.method $request.path"
  protocol_type                = "HTTP"
  tags                         = {}
  tags_all                     = {}
  disable_execute_api_endpoint = false

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
  api_id                 = aws_apigatewayv2_api.my_http_api.id
  connection_type        = "INTERNET"
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = "arn:aws:lambda:us-east-1:730335278778:function:increment_viewcount"
  payload_format_version = "1.0"
  request_parameters     = {}
  request_templates      = {}
  timeout_milliseconds   = 30000
}

resource "aws_iam_role" "lambda_execution_role" {
  name                 = "DBAccess"
  path                 = "/service-role/"
  managed_policy_arns  = [
    "arn:aws:iam::730335278778:policy/service-role/AWSLambdaBasicExecutionRole-48bf65f4-fb11-448a-9eee-76796d6743ce",
    "arn:aws:iam::730335278778:policy/service-role/AWSLambdaMicroserviceExecutionRole-1358459c-23d8-4862-95bf-f6ccf90686bb"
  ]
  max_session_duration = 3600
  tags                 = {}
  tags_all             = {}
  assume_role_policy   = jsonencode({
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
