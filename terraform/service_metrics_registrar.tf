# Copyright 2021 the Exposure Notifications Verification Server authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

resource "google_service_account" "metrics-registrar" {
  project      = var.project
  account_id   = "en-ver-metrics-registrar-sa"
  display_name = "Verification Metrics Registrar"
}

resource "google_service_account_iam_member" "cloudbuild-deploy-metrics-registrar" {
  service_account_id = google_service_account.metrics-registrar.id
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.cloudbuild_email}"
}

resource "google_project_iam_member" "metrics-registrar-observability" {
  for_each = local.observability_iam_roles
  project  = var.project
  role     = each.key
  member   = "serviceAccount:${google_service_account.metrics-registrar.email}"
}

resource "google_cloud_run_service" "metrics-registrar" {
  name     = "metrics-registrar"
  location = var.region

  autogenerate_revision_name = true

  metadata {
    annotations = merge(
      local.default_service_annotations,
      var.default_service_annotations_overrides,
      lookup(var.service_annotations, "metrics-registrar", {})
    )
  }

  template {
    spec {
      service_account_name = google_service_account.metrics-registrar.email

      containers {
        image = "gcr.io/${var.project}/github.com/google/exposure-notifications-verification-server/metrics-registrar:initial"

        resources {
          limits = {
            cpu    = "1000m"
            memory = "1G"
          }
        }


        dynamic "env" {
          for_each = merge(
            local.gcp_config,
            local.observability_config,
            local.metrics_registrar_config,

            // This MUST come last to allow overrides!
            lookup(var.service_environment, "_all", {}),
            lookup(var.service_environment, "metrics-registrar", {}),
          )

          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }

    metadata {
      annotations = merge(
        local.default_revision_annotations,
        var.default_revision_annotations_overrides,
        { "autoscaling.knative.dev/maxScale" = "1" },
        lookup(var.revision_annotations, "metrics-registrar", {})
      )
    }
  }

  depends_on = [
    google_project_service.services["run.googleapis.com"],

    google_project_iam_member.metrics-registrar-observability,

    null_resource.build,
    null_resource.migrate,
  ]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"],
      metadata[0].annotations["run.googleapis.com/ingress-status"],
      metadata[0].annotations["serving.knative.dev/creator"],
      metadata[0].annotations["serving.knative.dev/lastModifier"],
      metadata[0].labels["cloud.googleapis.com/location"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].annotations["serving.knative.dev/creator"],
      template[0].metadata[0].annotations["serving.knative.dev/lastModifier"],
      template[0].spec[0].containers[0].image,
    ]
  }
}

output "metrics-registrar_url" {
  value = google_cloud_run_service.metrics-registrar.status.0.url
}
