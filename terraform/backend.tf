terraform {
  backend "s3" {
    bucket = "terraform"
    key    = "subpath-"

    endpoint   = "https://minio.cpinnov.run"
    access_key = "SWKaKwZ3xtWQ6bNFs4Su"
    secret_key = "fHWaBZxaDagarD4Edv9c"

    region                      = "main"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
