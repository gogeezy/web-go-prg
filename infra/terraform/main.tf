resource "yandex_vpc_network" "diploma" {
  name = "diploma-network"
}

resource "yandex_vpc_subnet" "diploma" {
  name           = "diploma-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.diploma.id
  v4_cidr_blocks = ["10.10.0.0/24"]
}
