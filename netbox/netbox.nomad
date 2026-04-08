variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  stack      = "netbox"
  version    = "1.0.0"
  team       = "platform"

  time_zone = "Europe/Stockholm"

  netbox_image_tag = "docker.io/netboxcommunity/netbox:latest"
  netbox_cpu       = 1000
  netbox_memory    = 2048
  granian_workers  = "2"

  redis_image_tag = "redis/redis-stack-server:latest"
  redis_host      = "127.0.0.1"
  redis_port      = 6379
  redis_ssl       = false
  redis_cpu       = 500
  redis_memory    = 256
}

job "netbox" {
  meta {
    Deployer   = "${var.deployer}"
    CostCentre = "dev"
  }

  datacenters = var.datacenter
  type        = "service"
  priority    = 90

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = false
    attempts       = 3
    interval       = "24h"
  }

  group "netbox" {
    count = 1

    #    spread {
    #      attribute    = "${node.unique.name}"
    #      weight       = 100
    #    }

    constraint {
      attribute = "${node.unique.name}"
      value     = "ubuntu-03"
    }

    #    affinity {
    #      attribute    = "${node.unique.name}"
    #      value        = "ubuntu-01"
    #      weight       = 75
    #    }

    vault {
      policies = ["nomad-workloads", "netbox"]
    }

    network {
      mode = "bridge"

      port "http" {
        to = 8080
      }
    }

    service {
      name = "netbox"
      port = "http"
      tags = []

      connect {
        sidecar_service {}
      }

      check {
        type         = "http"
        path         = "/login/"
        interval     = "30s"
        timeout      = "10s"
        task         = "netbox"
        address_mode = "alloc"
      }
    }

    volume "netbox-media" {
      type      = "host"
      source    = "netbox-media"
      read_only = false
    }

    volume "redis-data" {
      type      = "host"
      source    = "redis-data"
      read_only = false
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "5m"
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    task "netbox" {
      driver = "docker"

      config {
        image        = var.netbox_image_tag
        ports        = ["http"]
        security_opt = ["no-new-privileges:true"]
        volumes = [
          "local/extra.py:/etc/netbox/config/extra.py"
        ]
      }

      volume_mount {
        volume      = "netbox-media"
        destination = "/opt/netbox/netbox/media"
        read_only   = false
      }

      template {
        data        = <<EOT
import os

# API Token security - set peppers for v2 tokens from environment
# Format: {id: 'secret_value'}
pepper_0 = os.getenv('API_TOKEN_PEPPER_0', '')
API_TOKEN_PEPPERS = {
    0: pepper_0
} if pepper_0 else {}
EOT
        destination = "local/extra.py"
      }

      template {
        data        = <<EOT
{{ with secret "secret/data/netbox" }}
DB_HOST={{ .Data.data.DB_HOST }}
DB_NAME={{ .Data.data.DB_NAME }}
DB_USER={{ .Data.data.DB_USER }}
DB_PASSWORD={{ .Data.data.DB_PASSWORD }}
SECRET_KEY={{ .Data.data.SECRET_KEY }}
API_TOKEN_PEPPER_0={{ .Data.data.API_TOKEN_PEPPER_0 }}
{{ end }}
EOT
        destination = "secrets/netbox.env"
        env         = true
      }

      env {
        TZ              = var.time_zone
        REDIS_HOST      = var.redis_host
        REDIS_PORT      = var.redis_port
        REDIS_SSL       = var.redis_ssl
        GRANIAN_WORKERS = var.granian_workers
      }

      resources {
        cpu    = var.netbox_cpu
        memory = var.netbox_memory
      }

      restart {
        attempts = 3
        interval = "30m"
        delay    = "15s"
        mode     = "delay"
      }

      logs {
        max_files     = 1
        max_file_size = 10
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image   = var.redis_image_tag
        command = "redis-server"
        args = [
          "--appendonly", "yes",
          "--appendfsync", "everysec",
          "--save", "900 1",
          "--save", "300 10",
          "--save", "60 10000",
          "--port", "6379",
          "--bind", "127.0.0.1",
          "--dir", "/data"
        ]
      }

      volume_mount {
        volume      = "redis-data"
        destination = "/data"
        read_only   = false
      }

      resources {
        cpu    = var.redis_cpu
        memory = var.redis_memory
      }

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      restart {
        attempts = 3
        interval = "30m"
        delay    = "15s"
        mode     = "delay"
      }

      logs {
        max_files     = 1
        max_file_size = 10
      }
    }

    task "netbox-worker" {
      driver = "docker"

      config {
        image        = var.netbox_image_tag
        command      = "/opt/netbox/venv/bin/python"
        args         = ["/opt/netbox/netbox/manage.py", "rqworker"]
        security_opt = ["no-new-privileges:true"]
        volumes = [
          "local/extra.py:/etc/netbox/config/extra.py"
        ]
      }

      volume_mount {
        volume      = "netbox-media"
        destination = "/opt/netbox/netbox/media"
        read_only   = false
      }

      template {
        data        = <<EOT
import os

# API Token security - set peppers for v2 tokens from environment
# Format: {id: 'secret_value'}
pepper_0 = os.getenv('API_TOKEN_PEPPER_0', '')
API_TOKEN_PEPPERS = {
    0: pepper_0
} if pepper_0 else {}
EOT
        destination = "local/extra.py"
      }

      template {
        data        = <<EOT
{{ with secret "secret/data/netbox" }}
DB_HOST={{ .Data.data.DB_HOST }}
DB_NAME={{ .Data.data.DB_NAME }}
DB_USER={{ .Data.data.DB_USER }}
DB_PASSWORD={{ .Data.data.DB_PASSWORD }}
SECRET_KEY={{ .Data.data.SECRET_KEY }}
API_TOKEN_PEPPER_0={{ .Data.data.API_TOKEN_PEPPER_0 }}
{{ end }}
EOT
        destination = "secrets/netbox.env"
        env         = true
      }

      env {
        TZ         = var.time_zone
        REDIS_HOST = var.redis_host
        REDIS_PORT = var.redis_port
        REDIS_SSL  = var.redis_ssl
      }

      resources {
        cpu    = var.netbox_cpu
        memory = var.netbox_memory
      }

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      restart {
        attempts = 10
        interval = "30m"
        delay    = "15s"
        mode     = "delay"
      }

      logs {
        max_files     = 1
        max_file_size = 10
      }
    }
  }
}