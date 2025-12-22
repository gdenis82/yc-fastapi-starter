terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  # Auth: specify either token or service_account_key_file
  token                     = var.token
  service_account_key_file  = var.service_account_key_file

  # Scope
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = "ru-central1-a"
}

variable "folder_id" {
  type = string
}

variable "cloud_id" {
  type = string
}

variable "token" {
  description = "OAuth token for Yandex Cloud (optional; use service_account_key_file for automation)."
  type        = string
  default     = null
  sensitive   = true
}

variable "service_account_key_file" {
  description = "Path to the service account JSON key file (optional)."
  type        = string
  default     = null
}

resource "yandex_iam_service_account" "sa" {
  name        = "tf-admin-sa"
  description = "Service account for managing infrastructure via Terraform"
  folder_id   = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "sa-roles" {
  for_each  = toset([
    "k8s.admin",
    "mdb.admin",
    "vpc.admin",
    "iam.serviceAccounts.user",
    "container-registry.admin",
    "lockbox.admin",
    "dns.admin"
  ])
  folder_id = var.folder_id
  role      = each.key
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_vpc_network" "k8s-network" {
  name = "k8s-network"
}

resource "yandex_vpc_subnet" "k8s-subnet-a" {
  name           = "k8s-subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.k8s-network.id
  v4_cidr_blocks = ["10.11.0.0/24"]
}

resource "yandex_vpc_subnet" "k8s-subnet-b" {
  name           = "k8s-subnet-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.k8s-network.id
  v4_cidr_blocks = ["10.12.0.0/24"]
}

resource "yandex_vpc_subnet" "k8s-subnet-d" {
  name           = "k8s-subnet-d"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.k8s-network.id
  v4_cidr_blocks = ["10.13.0.0/24"]
}

resource "yandex_iam_service_account" "k8s-sa" {
  name        = "k8s-sa"
  description = "K8s service account"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-pusher" {
  folder_id = var.folder_id
  role      = "container-registry.images.pusher"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "load-balancer-admin" {
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "compute-viewer" {
  folder_id = var.folder_id
  role      = "compute.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  name        = "k8s-cluster"
  network_id  = yandex_vpc_network.k8s-network.id
  service_account_id      = yandex_iam_service_account.k8s-sa.id
  node_service_account_id = yandex_iam_service_account.k8s-sa.id

  master {
    version = "1.31"
    regional {
      region = "ru-central1"

      location {
        zone      = yandex_vpc_subnet.k8s-subnet-a.zone
        subnet_id = yandex_vpc_subnet.k8s-subnet-a.id
      }

      location {
        zone      = yandex_vpc_subnet.k8s-subnet-b.zone
        subnet_id = yandex_vpc_subnet.k8s-subnet-b.id
      }

      location {
        zone      = yandex_vpc_subnet.k8s-subnet-d.zone
        subnet_id = yandex_vpc_subnet.k8s-subnet-d.id
      }
    }
    public_ip = true
  }

  release_channel = "RAPID"
  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
    yandex_resourcemanager_folder_iam_member.images-puller,
    yandex_resourcemanager_folder_iam_member.load-balancer-admin,
    yandex_resourcemanager_folder_iam_member.compute-viewer
  ]
}

resource "yandex_kubernetes_node_group" "k8s-node-group" {
  cluster_id  = yandex_kubernetes_cluster.k8s-cluster.id
  name        = "k8s-node-group"
  version     = "1.31"

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = [
        yandex_vpc_subnet.k8s-subnet-a.id,
        yandex_vpc_subnet.k8s-subnet-b.id,
        yandex_vpc_subnet.k8s-subnet-d.id
      ]
    }

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-ssd"
      size = 64
    }

    scheduling_policy {
      preemptible = false
    }
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
    location {
      zone = "ru-central1-b"
    }
  }
}

resource "yandex_container_registry" "registry" {
  name = "k8s-registry"
}

resource "yandex_vpc_address" "addr" {
  name = "fastapi-address"
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

resource "yandex_dns_zone" "zone1" {
  name        = "tryout-zone"
  description = "DNS zone for tryout.site"
  zone        = "tryout.site."
  public      = true
}

resource "yandex_dns_recordset" "rs1" {
  zone_id = yandex_dns_zone.zone1.id
  name    = "tryout.site."
  type    = "A"
  ttl     = 600
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

# Network Load Balancer is managed by Kubernetes Service/Ingress automatically.
# Manual creation in TF is not recommended for Managed K8s as it won't track dynamic nodes.

resource "yandex_mdb_postgresql_cluster" "postgres-cluster" {
  name        = "postgres-cluster"
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.k8s-network.id

  config {
    version = 16
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 10
    }
  }

  database {
    name  = "fastapi_db"
    owner = "db_user"
  }

  user {
    name     = "db_user"
    password = var.db_password
  }

  host {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.k8s-subnet-a.id
  }
}

variable "db_password" {
  description = "Password for PostgreSQL user"
  type        = string
  sensitive   = true
}

resource "yandex_lockbox_secret" "app-secrets" {
  name        = "app-secrets"
  description = "Secrets for FastAPI application"
}

resource "yandex_lockbox_secret_version" "app-secrets-v1" {
  secret_id = yandex_lockbox_secret.app-secrets.id
  entries {
    key        = "db_password"
    text_value = var.db_password
  }
  entries {
    key        = "fastapi_key"
    text_value = var.fastapi_key
  }
}

variable "fastapi_key" {
  description = "Secret key for FastAPI application"
  type        = string
  sensitive   = true
}

output "lockbox_secret_id" {
  value = yandex_lockbox_secret.app-secrets.id
}

output "db_host" {
  value = yandex_mdb_postgresql_cluster.postgres-cluster.host[0].fqdn
}

output "db_name" {
  value = "fastapi_db"
}

output "db_user" {
  value = "db_user"
}

output "cluster_id" {
  value = yandex_kubernetes_cluster.k8s-cluster.id
}

output "registry_id" {
  value = yandex_container_registry.registry.id
}

output "external_ip" {
  value = yandex_vpc_address.addr.external_ipv4_address[0].address
}
