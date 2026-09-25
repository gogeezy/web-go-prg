
resource "yandex_kubernetes_cluster" "diploma" {
  name        = "diploma-k8s"
  description = "Managed Kubernetes cluster for DevOps diploma"

  network_id = yandex_vpc_network.diploma.id

  master {
    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.diploma.id
    }

    public_ip = true
  }

  service_account_id = yandex_iam_service_account.k8s.id

  node_service_account_id = yandex_iam_service_account.k8s.id

  release_channel = "REGULAR"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_agent,
    yandex_resourcemanager_folder_iam_member.vpc_admin,
    yandex_resourcemanager_folder_iam_member.images_puller
  ]
}
