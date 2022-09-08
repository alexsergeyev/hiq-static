provider "aws" {
  region  = "eu-north-1"
  profile = "hiqdemo"
}

terraform {
  cloud {
    organization = "hiqdemo"

    workspaces {
      name = "static-demo"
    }
  }
}
