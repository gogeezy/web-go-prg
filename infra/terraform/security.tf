variable "admin_cidr" {
  description = "Public IPv4 address allowed to access Kubernetes API"
  type        = string
}

resource "yandex_vpc_security_group" "diploma" {
  name       = "diploma-k8s-sg"
  network_id = yandex_vpc_network.diploma.id

  # Обмен данными между master и рабочими узлами.
  ingress {
    protocol          = "ANY"
    predefined_target = "self_security_group"
  }

  # Сетевой обмен Pod и Service внутри Kubernetes.
  ingress {
    protocol       = "ANY"
    v4_cidr_blocks = ["10.96.0.0/16", "10.112.0.0/16"]
  }

  # Проверки доступности со стороны балансировщика.
  ingress {
    protocol          = "TCP"
    from_port         = 0
    to_port           = 65535
    predefined_target = "loadbalancer_healthchecks"
  }

  # Служебные проверки доступности.
  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Управление Kubernetes только с нашего сервера.
  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = [var.admin_cidr]
  }

  ingress {
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = [var.admin_cidr]
  }

  # Доступ к приложению через NGINX Ingress и Network Load Balancer.
  ingress {
    protocol       = "TCP"
    from_port      = 30000
    to_port        = 32767
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Исходящие подключения, включая скачивание образов.
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
