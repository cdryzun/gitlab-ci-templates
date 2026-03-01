terraform {
  backend "s3" {
    bucket = "terraform"
    key    = "subpath-"

    # SECURITY: Configure these credentials via environment variables
    # DO NOT commit real credentials to version control
    # export AWS_ACCESS_KEY_ID=your-access-key
    # export AWS_SECRET_ACCESS_KEY=your-secret-key
    # Or use: terraform login / terraform cloud

    endpoint                    = var.minio_endpoint
    region                      = "main"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
