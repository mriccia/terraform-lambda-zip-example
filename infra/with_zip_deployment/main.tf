provider "aws" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

variable "lambda_root" {
  default = "../../code/HelloWorldLambda/"
}
# Install Python dependencies
resource "null_resource" "install_dependencies" {
  provisioner "local-exec" {
    command = "pip install -r ${var.lambda_root}/requirements.txt -t ${var.lambda_root}/"
  }

  triggers = {
    dependencies_versions = filemd5("${var.lambda_root}/requirements.txt")
    source_versions = filemd5("${var.lambda_root}/app.py")
  }
}

# Create the Lambda ZIP file
data "archive_file" "python_lambda_package" {
  type = "zip"
  source_dir = "${var.lambda_root}"
  output_path = "helloworldlambda.zip"
}

# Create the Lambda function definition
resource "aws_lambda_function" "helloworldFunction" {

  function_name = "helloworldFunction"

  filename = "helloworldlambda.zip"

  handler = "app.lambda_handler"
  runtime = "python3.11"

  role = aws_iam_role.helloworldFunctionRole.arn
  source_code_hash = filebase64sha256(data.archive_file.python_lambda_package.output_path)

  timeout     = "200"
  memory_size = "256"
}

# Define the Lambda function permissions
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "helloworldFunctionRole" {
  name               = "helloworldFunctionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
resource "aws_iam_role_policy_attachment" "helloworldFunctionRolePolicy" {
  role       = aws_iam_role.helloworldFunctionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create the APIGW route configurations
resource "aws_api_gateway_rest_api" "helloworld_apigw" {
  name        = "helloworld_apigw"
  description = "Hello World API Gateway"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}
resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.helloworld_apigw.id
  parent_id   = aws_api_gateway_rest_api.helloworld_apigw.root_resource_id
  path_part   = "hello"
}
resource "aws_api_gateway_method" "sayhello" {
  rest_api_id   = aws_api_gateway_rest_api.helloworld_apigw.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sayhello-lambda" {

  rest_api_id = aws_api_gateway_rest_api.helloworld_apigw.id
  resource_id = aws_api_gateway_method.sayhello.resource_id
  http_method = aws_api_gateway_method.sayhello.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"

  uri = aws_lambda_function.helloworldFunction.invoke_arn
}

resource "aws_lambda_permission" "apigw-sayhelloHandler" {

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.helloworldFunction.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.helloworld_apigw.execution_arn}/*/${aws_api_gateway_method.sayhello.http_method}${aws_api_gateway_resource.hello.path}"
}

resource "aws_api_gateway_deployment" "productapistageprod" {

  depends_on = [
    aws_api_gateway_integration.sayhello-lambda
  ]

  rest_api_id = aws_api_gateway_rest_api.helloworld_apigw.id
  stage_name  = "prod"
}

# Print out the Invoke URL
output "deployment_invoke_url" {
  description = "Deployment invoke url"
  value       = "${aws_api_gateway_deployment.productapistageprod.invoke_url}/hello"
}
