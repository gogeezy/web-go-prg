
resource "yandex_kubernetes_cluster" "diploma" {
  name        = "diploma-k8s"
  description = "Managed Kubernetes cluster for DevOps diploma"

  network_id = yandex_vpc_network.diploma.id

  cluster_ipv4_range = "10.96.0.0/16"
  service_ipv4_range = "10.112.0.0/16"

  master {
    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.diploma.id
    }

    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.diploma.id]
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
