terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    random = {
      source = "hashicorp/random"
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
    "admin",
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
  folder_id   = var.folder_id
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

resource "yandex_resourcemanager_folder_iam_member" "logging-writer" {
  folder_id = var.folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-sa-lockbox-payload" {
  folder_id = var.folder_id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_vpc_security_group" "k8s-main-sg" {
  name        = "k8s-main-sg"
  network_id  = yandex_vpc_network.k8s-network.id

  ingress {
    protocol          = "ANY"
    description       = "Allow all inside security group"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    protocol       = "ANY"
    description    = "Allow all inside network"
    v4_cidr_blocks = ["10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
  }

  ingress {
    protocol       = "ANY"
    description    = "Allow all inside VPC"
    v4_cidr_blocks = ["10.11.0.0/16", "10.12.0.0/16", "10.13.0.0/16"]
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow port 5432 for PostgreSQL from everywhere"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5432
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow NodePort range for LoadBalancer"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol          = "TCP"
    description       = "Allow health checks from load balancer"
    predefined_target = "loadbalancer_healthchecks"
    port              = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow Kubernetes API"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow nodes communication"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outgoing"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  name        = "k8s-cluster"
  network_id  = yandex_vpc_network.k8s-network.id
  service_account_id      = yandex_iam_service_account.k8s-sa.id
  node_service_account_id = yandex_iam_service_account.k8s-sa.id

  master {
    version = "1.31"
    zonal {
      zone      = yandex_vpc_subnet.k8s-subnet-a.zone
      subnet_id = yandex_vpc_subnet.k8s-subnet-a.id
    }
    public_ip = true
    security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]

    master_logging {
      enabled = true
      folder_id = var.folder_id
      kube_apiserver_enabled = true
      cluster_autoscaler_enabled = true
      events_enabled = true
      audit_enabled = true
    }
  }

  release_channel = "RAPID"

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
    yandex_resourcemanager_folder_iam_member.images-puller,
    yandex_resourcemanager_folder_iam_member.load-balancer-admin,
    yandex_resourcemanager_folder_iam_member.compute-viewer,
    yandex_resourcemanager_folder_iam_member.logging-writer
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
      security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]
      subnet_ids         = [
        yandex_vpc_subnet.k8s-subnet-a.id
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

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "tryout.site"
}

resource "yandex_dns_zone" "zone1" {
  name        = "fastapi-zone"
  description = "DNS zone for ${var.domain_name}"
  zone        = "${var.domain_name}."
  public      = true
}

resource "yandex_dns_recordset" "rs1" {
  zone_id = yandex_dns_zone.zone1.id
  name    = "${var.domain_name}."
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
  security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]

  config {
    version = 16
    postgresql_config = {
      max_connections = 100
      log_min_duration_statement = 500
      log_checkpoints = true
      log_connections = true
      log_disconnections = true
      log_lock_waits = true
    }
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 10
    }
    access {
      web_sql       = true
      data_transfer = true
    }
  }

  host {
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.k8s-subnet-a.id
    assign_public_ip = true
  }

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

resource "yandex_mdb_postgresql_database" "fastapi_db" {
  cluster_id = yandex_mdb_postgresql_cluster.postgres-cluster.id
  name       = "fastapi_db"
  owner      = yandex_mdb_postgresql_user.db_user.name
}

resource "yandex_mdb_postgresql_user" "db_user" {
  cluster_id = yandex_mdb_postgresql_cluster.postgres-cluster.id
  name       = "db_user"
  password   = local.actual_db_password
}

variable "db_password" {
  description = "Password for PostgreSQL user (if empty, a random one will be generated)"
  type        = string
  sensitive   = true
  default     = ""
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "fastapi_key" {
  length           = 32
  special          = true
}

locals {
  actual_db_password = var.db_password != "" ? var.db_password : random_password.db_password.result
  actual_fastapi_key = var.fastapi_key != "" ? var.fastapi_key : random_password.fastapi_key.result
}

resource "yandex_lockbox_secret" "app-secrets" {
  name        = "app-secrets"
  description = "Secrets for FastAPI application"
}

resource "yandex_lockbox_secret_version" "app-secrets-v1" {
  secret_id = yandex_lockbox_secret.app-secrets.id
  entries {
    key        = "db_password"
    text_value = local.actual_db_password
  }
  entries {
    key        = "fastapi_key"
    text_value = local.actual_fastapi_key
  }

  lifecycle {
    ignore_changes = [
      entries
    ]
  }
}

variable "fastapi_key" {
  description = "Secret key for FastAPI application (if empty, a random one will be generated)"
  type        = string
  sensitive   = true
  default     = ""
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

output "registry_id" {
  value = yandex_container_registry.registry.id
}

output "external_ip" {
  value = yandex_vpc_address.addr.external_ipv4_address[0].address
}

output "domain_name" {
  value = var.domain_name
}

output "k8s_cluster_id" {
  value = yandex_kubernetes_cluster.k8s-cluster.id
}
