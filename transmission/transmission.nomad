variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone         = "Europe/Stockholm"
  image_tag         = "lscr.io/linuxserver/transmission:latest"
  transmission_port = 9091
  puid              = "1000"
  pgid              = "1000"

  cpu    = 200
  memory = 256
}

job "transmission" {

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

  group "transmission" {
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
      mode = "bridge"
      port "web" {
        to = var.transmission_port
      }
    }

    service {
      name = "transmission"
      port = "web"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.transmission.rule=Host(`transmission-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.transmission.entrypoints=https",
        "traefik.http.routers.transmission.tls=true",
        "traefik.http.routers.transmission.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/transmission/web/"
        port     = "web"
        interval = "10s"
        timeout  = "3s"
      }
    }

    volume "transmission-config" {
      type      = "host"
      source    = "transmission-config"
      read_only = false
    }

    volume "transmission-watch" {
      type      = "host"
      source    = "transmission-watch"
      read_only = false
    }

    volume "torrents" {
      type      = "host"
      source    = "torrents"
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

    task "transmission" {
      driver = "docker"

      config {
        image        = var.image_tag
        volumes      = ["/etc/localtime:/etc/localtime:ro"]
        security_opt = ["no-new-privileges"]
      }

      volume_mount {
        volume      = "transmission-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "transmission-watch"
        destination = "/watch"
        read_only   = false
      }

      volume_mount {
        volume      = "torrents"
        destination = "/downloads"
        read_only   = false
      }

      env {
        TZ   = var.time_zone
        PUID = var.puid
        PGID = var.pgid
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