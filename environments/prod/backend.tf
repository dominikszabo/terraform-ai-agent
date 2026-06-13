terraform {
  backend "s3" {
    bucket         = "tf-state-380093117861"
    key            = "env:prod/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "tf-state-locks"
    encrypt        = true
  }
}
