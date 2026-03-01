provider "gitlab" {
  token    = var.gitlab_token
  # SECURITY: Configure GitLab URL via environment variable
  # export GITLAB_BASE_URL=https://your-gitlab-instance.com/api/v4/
  base_url = var.gitlab_base_url
}

resource "gitlab_instance_variable" "main" {
  for_each      = var.vault_key
  key           = each.value
  value         = file("${path.module}/${each.value}.vault")
  protected     = false
  masked        = true
  variable_type = "file"
}
