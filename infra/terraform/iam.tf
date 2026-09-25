
# Service account for Managed Kubernetes

resource "yandex_iam_service_account" "k8s" {
  name        = "diploma-k8s-sa"
  description = "Service account for diploma Kubernetes cluster"
  folder_id   = var.folder_id
}

# Permissions required by the cluster

resource "yandex_resourcemanager_folder_iam_member" "k8s_agent" {
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc_admin" {
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images_puller" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}
