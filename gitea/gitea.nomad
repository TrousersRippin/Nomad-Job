variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone = "Europe/Stockholm"
  image_tag = "ghcr.io/go-gitea/gitea:latest-rootless"
  user_id   = "1000"
  user_gid  = "1000"

  cpu    = 500
  memory = 512
}

job "gitea" {

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

  group "gitea" {
    count = 1

    #    spread {
    #      attribute = "${node.unique.name}"
    #      weight    = 100
    #    }

    constraint {
      attribute = "${node.unique.name}"
      value     = "ubuntu-03"
    }

    #    affinity {
    #      attribute = "${node.unique.name}"
    #      value     = "ubuntu-01"
    #      weight    = 75
    #    }

    network {
      port "http" {
        to = 3000
      }
      port "ssh" {
        to = 2222
      }
    }

    service {
      name = "gitea"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.gitea.rule=Host(`gitea-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.gitea.entrypoints=https",
        "traefik.http.routers.gitea.tls=true",
        "traefik.http.routers.gitea.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/api/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "gitea-config" {
      type      = "host"
      source    = "gitea-config"
      read_only = false
    }

    volume "gitea-data" {
      type      = "host"
      source    = "gitea-data"
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

    task "gitea" {
      driver = "docker"

      config {
        image        = var.image_tag
        ports        = ["http", "ssh"]
        volumes      = ["/etc/localtime:/etc/localtime:ro"]
        security_opt = ["no-new-privileges"]
      }

      volume_mount {
        volume      = "gitea-config"
        destination = "/etc/gitea"
        read_only   = false
      }

      volume_mount {
        volume      = "gitea-data"
        destination = "/var/lib/gitea"
        read_only   = false
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