variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone        = "Europe/Stockholm"
  image_tag        = "docker.io/filebrowser/filebrowser:latest"
  filebrowser_port = 80
  puid             = "1000"
  pgid             = "1000"

  cpu    = 100
  memory = 128
}

job "filebrowser" {

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

  group "filebrowser" {
    count = 3

    #    spread {
    #      attribute    = "${node.unique.name}"
    #      weight       = 100
    #    }

    #    constraint {
    #      attribute    = "${node.unique.name}"
    #      value        = "ubuntu-03"
    #    }

    #    affinity {
    #      attribute    = "${node.unique.name}"
    #      value        = "ubuntu-01"
    #      weight       = 75
    #    }

    vault {
      policies    = ["nomad-workloads", "filebrowser"]
      change_mode = "restart"
    }

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "filebrowser"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.filebrowser.rule=Host(`filebrowser-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.filebrowser.entrypoints=https",
        "traefik.http.routers.filebrowser.tls=true",
        "traefik.http.routers.filebrowser.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "filebrowser-config" {
      type      = "host"
      source    = "filebrowser-config"
      read_only = false
    }

    volume "filebrowser-data" {
      type      = "host"
      source    = "filebrowser-data"
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

    task "filebrowser" {
      driver = "docker"

      config {
        image = var.image_tag
        ports = ["http"]
        volumes = [
          "/:/srv:rw",
          "/etc/localtime:/etc/localtime:ro"
        ]
        security_opt = ["no-new-privileges"]
      }

      volume_mount {
        volume      = "filebrowser-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "filebrowser-data"
        destination = "/database"
        read_only   = false
      }

      template {
        data        = <<-EOF
          {{ with secret "secret/data/filebrowser" }}
          {{ range $key, $value := .Data.data }}
          {{ $key }}={{ $value }}
          {{ end }}
          {{ end }}
      EOF
        destination = "secrets/filebrowser.env"
        env         = true
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