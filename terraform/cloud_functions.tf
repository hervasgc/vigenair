# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
data "local_file" "env_config_file" {
  filename = "${path.root}/../service/.env.yaml"
}

locals {
  service_environment_variables = yamldecode(data.local_file.env_config_file.content)
}

# Used only to compute a content hash so the Cloud Run deploy below re-runs
# whenever the service source changes; the archive itself is not uploaded
# anywhere ("gcloud run deploy --source" builds directly from the local
# "service/" directory via Cloud Build, using "service/Dockerfile").
data "archive_file" "service_source_code_archive" {
  type        = "zip"
  output_path = "${path.root}/service_source_code.zip"
  source_dir  = "${path.root}/../service"
  excludes = [
    ".env.yaml",
    ".gitignore",
    ".gcloudignore",
    "deploy.sh",
    "update_config.sh",
    "pylintrc",
  ]
}

# "google_cloud_run_v2_service" requires a pre-built container image, and the
# Google Terraform provider has no equivalent to
# "google_cloudfunctions2_function.build_config.source" for building straight
# from a local source directory. "gcloud run deploy --source" is the
# supported way to build and deploy a container to a real Cloud Run service
# in one step, so it is invoked here as a local-exec escape hatch, re-run
# whenever the source hash changes. It builds from "service/Dockerfile"
# (pinned to Python 3.10, matching the app's dependencies) rather than
# Buildpacks, which no longer offer a Python 3.10 runtime.
resource "null_resource" "vigenair_cloud_run_deploy" {
  triggers = {
    source_hash = data.archive_file.service_source_code_archive.output_sha256
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/../service"
    command     = <<-EOT
      gcloud run deploy vigenair \
        --project=${module.project_services.project_id} \
        --region=${var.region} \
        --source=. \
        --memory=32Gi \
        --cpu=8 \
        --timeout=540s \
        --concurrency=1 \
        --no-allow-unauthenticated \
        --env-vars-file=.env.yaml \
        --clear-base-image \
        --quiet
    EOT
  }

  depends_on = [
    time_sleep.wait_for_policy_propagation
  ]
}

# Read-only reference to the service deployed above. It is intentionally not
# managed as a "google_cloud_run_v2_service" resource: Terraform would fight
# the imperative "gcloud run deploy" over the container image/revision on
# every apply.
data "google_cloud_run_v2_service" "vigenair_service" {
  name     = "vigenair"
  project  = module.project_services.project_id
  location = var.region

  depends_on = [
    null_resource.vigenair_cloud_run_deploy
  ]
}

resource "google_eventarc_trigger" "vigenair_gcs_trigger" {
  name     = "vigenair-gcs-trigger"
  project  = module.project_services.project_id
  location = var.gcs_location

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.backend_service_bucket.name
  }

  service_account = data.google_compute_default_service_account.compute_service_agent.email

  destination {
    cloud_run_service {
      service = data.google_cloud_run_v2_service.vigenair_service.name
      region  = var.region
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "vigenair_eventarc_invoker" {
  project  = module.project_services.project_id
  location = var.region
  name     = data.google_cloud_run_v2_service.vigenair_service.name
  role     = "roles/run.invoker"
  member   = data.google_compute_default_service_account.compute_service_agent.member
}
