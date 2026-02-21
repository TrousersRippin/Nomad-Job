variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone   = "Europe/Stockholm"
  image_tag   = "ghcr.io/amir20/dozzle:latest"
  dozzle_port = ":8008"

  cpu    = 100
  memory = 128
}

job "dozzle" {

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

  group "dozzle" {
    count = 3

    #    constraint {
    #      attribute = "${node.unique.name}"
    #      value     = "ubuntu-02"
    #    }

    network {
      port "http" {
        to = 8008
      }
    }

    service {
      name = "dozzle"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dozzle.rule=Host(`dozzle-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.dozzle.entrypoints=https",
        "traefik.http.routers.dozzle.tls=true",
        "traefik.http.routers.dozzle.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/healthcheck"
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

    task "dozzle" {
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

      env {
        TZ                    = var.time_zone
        DOZZLE_ADDR           = var.dozzle_port
        DOZZLE_ENABLE_ACTIONS = "true"
        DOZZLE_NO_ANALYTICS   = "true"
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