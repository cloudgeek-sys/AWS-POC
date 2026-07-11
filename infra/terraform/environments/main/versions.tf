terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket  = "tf-state-371170753734-us-east-1-an"
    key     = "aws-poc/main/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
