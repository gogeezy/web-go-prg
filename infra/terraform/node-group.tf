
resource "yandex_kubernetes_node_group" "diploma" {
  cluster_id  = yandex_kubernetes_cluster.diploma.id
  name        = "diploma-node-group"
  description = "Worker nodes for DevOps diploma"

  instance_template {
    platform_id = "standard-v2"

    resources {
      cores  = 2
      memory = 4
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    network_interface {
      subnet_ids = [
        yandex_vpc_subnet.diploma.id
      ]

      nat = true
    }

    scheduling_policy {
      preemptible = false
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
  }
}
