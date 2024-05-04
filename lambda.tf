terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

#to collect aws region and account_id to create arns
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Store Datadog API key in AWS Secrets Manager
variable "secret_arn" {
  type        = string
  description = "Please enter aws secret arn of datadog api key"
}

#creating Datadog forwarder Lambda
resource "aws_cloudformation_stack" "datadog_forwarder" {
  name         = "datadog-forwarder-tf"
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
  parameters   = {
    DdApiKeySecretArn  = var.secret_arn,
    DdSite             = "datadoghq.com",
    FunctionName       = "datadog-forwarder-tf"
  }
  template_url = "https://datadog-cloudformation-template.s3.amazonaws.com/aws/forwarder/latest.yaml"
}


#Guarduty Event Rule for Findings
resource "aws_cloudwatch_event_rule" "main" {
  name          = "guardduty-finding-events"
  description   = "AWS GuardDuty event findings"
  event_pattern = file("${path.module}/event-pattern.json")
  depends_on = [
    aws_cloudformation_stack.datadog_forwarder
  ]
}

output "rule_arn" {
  value = aws_cloudwatch_event_rule.main.arn
  depends_on = [
    aws_cloudformation_stack.datadog_forwarder
  ]
}

#Adding Target as Datadog Lambda
resource "aws_cloudwatch_event_target" "DD_Lambda" {
  rule      = aws_cloudwatch_event_rule.main.name
  target_id = "DD_Lambda"
  arn       = join(":", ["arn:aws","lambda",data.aws_region.current.name,data.aws_caller_identity.current.account_id,"function","datadog-forwarder-tf"])
  depends_on = [
    aws_cloudformation_stack.datadog_forwarder
  ]
}

#Adding Trigger to Datadog Lambda
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = join(":", ["arn:aws","lambda",data.aws_region.current.name,data.aws_caller_identity.current.account_id,"function","datadog-forwarder-tf"])
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.main.arn
  depends_on = [
    aws_cloudformation_stack.datadog_forwarder
  ]
}