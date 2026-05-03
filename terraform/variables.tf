variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "late-data-demo"
}

variable "kinesis_shard_count" {
  description = "Number of Kinesis shards"
  type        = number
  default     = 1
}

variable "kinesis_retention_hours" {
  description = "How long Kinesis retains records (hours)"
  type        = number
  default     = 24
}

variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "glue_worker_type" {
  description = "Glue worker type"
  type        = string
  default     = "G.1X"
}

variable "glue_num_workers" {
  description = "Number of Glue workers"
  type        = number
  default     = 2
}
