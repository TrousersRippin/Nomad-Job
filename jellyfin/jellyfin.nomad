variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone     = "Europe/Stockholm"
  image_tag     = "lscr.io/linuxserver/jellyfin:latest"
  jellyfin_port = 8096
  puid          = "1000"
  pgid          = "1000"

  cpu    = 2000
  memory = 2048
}

job "jellyfin" {

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

  group "jellyfin" {
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
      mode = "bridge"
      port "web" {
        to = var.jellyfin_port
      }
    }

    service {
      name = "jellyfin"
      port = var.jellyfin_port
      #provider = "nomad"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellyfin.rule=Host(`jellyfin.thenoisykeyboard.com`)",
        "traefik.http.routers.jellyfin.entrypoints=https",
        "traefik.http.routers.jellyfin.tls=true",
        "traefik.http.routers.jellyfin.middlewares=internal-only@file",
      ]
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
      }
    }

    volume "jellyfin-config" {
      type            = "csi"
      source          = "jellyfin-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "jellyfin-cache" {
      type            = "csi"
      source          = "jellyfin-cache"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "torrents" {
      type            = "csi"
      source          = "torrents"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
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

    task "jellyfin" {
      driver = "docker"

      config {
        image        = var.image_tag
        volumes      = ["/etc/localtime:/etc/localtime:ro"]
        security_opt = ["no-new-privileges"]
      }

      volume_mount {
        volume      = "jellyfin-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "jellyfin-cache"
        destination = "/cache"
        read_only   = false
      }

      volume_mount {
        volume      = "torrents"
        destination = "/download"
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