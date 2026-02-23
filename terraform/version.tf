terraform {
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "3.15.0"
    }
  }
  required_version = ">= 1.1.7"
}
