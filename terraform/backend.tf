terraform {
  backend "s3" {
    bucket       = "project-bedrock-tfstate-alt-soe-025-4887"
    key          = "project-bedrock/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
