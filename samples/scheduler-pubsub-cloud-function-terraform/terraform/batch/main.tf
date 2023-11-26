resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "google_service_account" "default" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name}"
  project      = var.project_id
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.default.email}"
}

resource "google_pubsub_topic" "default" {
  name    = "${var.function_name}-topic"
  project = var.project_id
}

resource "google_storage_bucket" "default" {
  name                        = "${var.function_name}-gcf-source-${random_id.bucket_prefix.hex}" # Every bucket name must be globally unique
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true
}

data "archive_file" "default" {
  type        = "zip"
  output_path = "${var.function_name}.zip"
  source_dir  = var.source_dir
  excludes = [
    ".env"
  ]
}

resource "google_storage_bucket_object" "default" {
  name   = "${var.function_name}.zip"
  bucket = google_storage_bucket.default.name
  source = data.archive_file.default.output_path # Path to the zipped function source code
}

resource "google_cloudfunctions2_function" "default" {
  name     = var.function_name
  location = var.location
  project  = var.project_id

  build_config {
    runtime               = var.runtime
    entry_point           = var.entrypoint
    environment_variables = var.build_env_variables
    source {
      storage_source {
        bucket = google_storage_bucket.default.name
        object = google_storage_bucket_object.default.name
      }
    }
  }

  service_config {
    max_instance_count    = 3
    min_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    environment_variables = var.runtime_env_variables
    dynamic "secret_environment_variables" {
      for_each = var.runtime_secret_env_variables != null ? var.runtime_secret_env_variables : []
      iterator = sev
      content {
        key        = sev.value.key
        project_id = var.project_id
        secret     = sev.value.secret
        version    = sev.value.version
      }
    }
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.default.email
  }

  event_trigger {
    trigger_region = var.location
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.default.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}

resource "google_cloud_scheduler_job" "scheduler" {
  name      = "${var.function_name}-scheduler"
  project   = var.project_id
  region    = var.location
  schedule  = var.schedule
  time_zone = "Asia/Tokyo"

  pubsub_target {
    topic_name = google_pubsub_topic.default.id
    data       = var.message
  }
}
