variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone = "Europe/Stockholm"
  image_tag = "docker.io/plexinc/pms-docker:latest"
  plex_port = 32400
  plex_uid  = "1000"
  plex_gid  = "1000"
  # plex_claim          = "claim-xxxxxxxxxxxx"
  plex_version = "docker"

  cpu    = 2000
  memory = 2048
}

job "plex" {

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

  group "plex" {
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

    network {
      mode = "host"
    }

    service {
      name = "plex"
      port = var.plex_port

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.plex.rule=Host(`plex-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.plex.entrypoints=https",
        "traefik.http.routers.plex.tls=true",
        "traefik.http.routers.plex.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/identity"
        interval = "30s"
        timeout  = "5s"
      }
    }

    volume "plex-config" {
      type      = "host"
      source    = "plex-config"
      read_only = false
    }

    volume "plex-transcode" {
      type      = "host"
      source    = "plex-transcode"
      read_only = false
    }

    volume "torrents" {
      type      = "host"
      source    = "torrents"
      read_only = true
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

    task "plex" {
      driver = "docker"

      config {
        image        = var.image_tag
        network_mode = "host"
        volumes      = ["/etc/localtime:/etc/localtime:ro"]
        security_opt = ["no-new-privileges:true"]
      }

      volume_mount {
        volume      = "plex-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "plex-transcode"
        destination = "/transcode"
        read_only   = false
      }

      volume_mount {
        volume      = "torrents"
        destination = "/download"
        read_only   = false
      }

      env {
        TZ       = var.time_zone
        PLEX_UID = var.plex_uid
        PLEX_GID = var.plex_gid
        # PLEX_CLAIM      = var.plex_claim
        VERSION = var.plex_version
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