variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  cpu    = 100
  memory = 128
}

job "nginx" {

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

  group "nginx" {
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

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "nginx"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.nginx.rule=Host(`nginx.thenoisykeyboard.com`)",
        "traefik.http.routers.nginx.entrypoints=https",
        "traefik.http.routers.nginx.tls=true",
        "traefik.http.routers.nginx.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
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

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:latest"
        ports = ["http"]
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