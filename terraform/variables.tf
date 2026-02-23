variable "gitlab_token" {
  type      = string
  sensitive = true
}

variable "vault_key" {
  type = set(string)
}
