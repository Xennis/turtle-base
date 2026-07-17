provider "google" {
  project = var.project_id
}

# Enables the Drive API - the one part of the Drive-sync OAuth setup
# checklist that's actually automatable. Everything else (Google Auth
# Platform branding/audience/scopes, and the Desktop/Android/Web
# application OAuth Client IDs) has no Terraform resource and no
# gcloud/REST API alternative - it's Console-only, see README.md.
resource "google_project_service" "drive" {
  service = "drive.googleapis.com"

  # Don't disable the API for the whole project on `tofu destroy` -
  # other things may depend on it by then.
  disable_on_destroy = false
}
