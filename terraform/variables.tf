variable "gitlab_token" {
  type      = string
  sensitive = true
}

variable "gitlab_base_url" {
  type      = string
  sensitive = true
}

variable "minio_endpoint" {
  type      = string
  sensitive = true
}

variable "vault_key" {
  type = set(string)
}
