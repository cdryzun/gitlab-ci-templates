provider "gitlab" {
  token    = var.gitlab_token
  base_url = "https://gitlab-ee.cpinnov.run/api/v4/"
}

resource "gitlab_instance_variable" "main" {
  for_each      = var.vault_key
  key           = each.value
  value         = file("${path.module}/${each.value}.vault")
  protected     = false
  masked        = true
  variable_type = "file"
}
