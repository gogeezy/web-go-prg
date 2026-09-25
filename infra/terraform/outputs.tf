output "network_id" {
  description = "ID of the diploma VPC network"
  value       = yandex_vpc_network.diploma.id
}

output "subnet_id" {
  description = "ID of the diploma subnet"
  value       = yandex_vpc_subnet.diploma.id
}

output "kubernetes_cluster_id" {
  description = "Managed Kubernetes cluster ID"
  value       = yandex_kubernetes_cluster.diploma.id
}

output "kubernetes_cluster_name" {
  description = "Managed Kubernetes cluster name"
  value       = yandex_kubernetes_cluster.diploma.name
}

output "node_group_id" {
  description = "Managed Kubernetes node group ID"
  value       = yandex_kubernetes_node_group.diploma.id
}

output "node_group_name" {
  description = "Managed Kubernetes node group name"
  value       = yandex_kubernetes_node_group.diploma.name
}
