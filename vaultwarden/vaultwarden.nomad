variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone        = "Europe/Stockholm"
  image_tag        = "ghcr.io/dani-garcia/vaultwarden:latest"
  vaultwarden_port = 80
  user_id          = "1000"
  user_gid         = "1000"

  cpu    = 500
  memory = 512
}

job "vaultwarden" {

  meta {
    deployer = "${var.deployer}"
    version  = "${var.version}"
    team     = "${var.team}"
  }

  datacenters = var.datacenter
  type        = "service"

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = false
    attempts       = 3
    interval       = "24h"
  }

  group "vaultwarden" {
    count = 1

    #    spread {
    #      attribute = "${node.unique.name}"
    #      weight    = 100
    #    }

    constraint {
      attribute = "${node.unique.name}"
      value     = "ubuntu-01"
    }

    #    affinity {
    #      attribute = "${node.unique.name}"
    #      value     = "ubuntu-01"
    #      weight    = 75
    #    }

    vault {
      policies    = ["nomad-workloads", "vaultwarden"]
      change_mode = "restart"
    }

    network {
      mode = "bridge"
      port "http" {
        to = var.vaultwarden_port
      }
    }

    service {
      name = "vaultwarden"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vaultwarden.rule=Host(`vaultwarden-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.vaultwarden.entrypoints=https",
        "traefik.http.routers.vaultwarden.tls=true",
        "traefik.http.routers.vaultwarden.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/alive"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "vaultwarden-data" {
      type      = "host"
      source    = "vaultwarden-data"
      read_only = false
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image        = var.image_tag
        ports        = ["http"]
        volumes      = ["/etc/localtime:/etc/localtime:ro"]
        security_opt = ["no-new-privileges"]
      }

      volume_mount {
        volume      = "vaultwarden-data"
        destination = "/data"
        read_only   = false
      }

      template {
        data        = <<-EOF
          {{ with secret "secret/data/vaultwarden" }}
          {{ range $key, $value := .Data.data }}
          {{ $key }}={{ $value }}
          {{ end }}
          {{ end }}
      EOF
        destination = "secrets/vaultwarden.env"
        env         = true
      }

      env {
        TZ       = var.time_zone
        USER_UID = var.user_id
        USER_GID = var.user_gid
      }

      resources {
        cpu    = var.cpu
        memory = var.memory
      }

      logs {
        max_files     = 1
        max_file_size = 10
        disabled      = false
      }
    }
  }
}