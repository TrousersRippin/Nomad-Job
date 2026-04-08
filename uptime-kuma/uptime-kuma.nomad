variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone        = "Europe/Stockholm"
  image_tag        = "ghcr.io/louislam/uptime-kuma:2-rootless"
  uptime_kuma_port = 3001

  cpu    = 200
  memory = 256
}

job "uptime-kuma" {

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

  group "uptime-kuma" {
    count = 1

    #    spread {
    #      attribute    = "${node.unique.name}"
    #      weight       = 100
    #    }

    constraint {
      attribute = "${node.unique.name}"
      value     = "ubuntu-02"
    }

    #    affinity {
    #      attribute    = "${node.unique.name}"
    #      value        = "ubuntu-01"
    #      weight       = 75
    #    }

    network {
      mode = "bridge"
      port "http" {
        to = var.uptime_kuma_port
      }
    }

    service {
      name = "uptime-kuma"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.uptime-kuma.rule=Host(`uptime-kuma-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.uptime-kuma.entrypoints=https",
        "traefik.http.routers.uptime-kuma.tls=true",
        "traefik.http.routers.uptime-kuma.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "uptime-kuma-data" {
      type      = "host"
      source    = "uptime-kuma-data"
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

    task "uptime-kuma" {
      driver = "docker"

      config {
        image = var.image_tag
        ports = ["http"]
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock",
          "/etc/localtime:/etc/localtime:ro"
        ]
        security_opt = ["no-new-privileges"]
      }

      volume_mount {
        volume      = "uptime-kuma-data"
        destination = "/app/data"
        read_only   = false
      }

      env {
        TZ = var.time_zone
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