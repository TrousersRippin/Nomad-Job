variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone           = "Europe/Stockholm"
  paperless_image_tag = "ghcr.io/paperless-ngx/paperless-ngx:latest"
  paperless_port      = 8000
  paperless_cpu       = 1000
  paperless_memory    = 1024

  redis_image_tag = "docker.io/redis:8-alpine"
  redis_host      = "127.0.0.1"
  redis_port      = 6379
  redis_ssl       = false
  redis_cpu       = 200
  redis_memory    = 128
}

job "paperless" {

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

  group "paperless" {
    count = 1

    #    spread {
    #      attribute = "${node.unique.name}"
    #      weight    = 100
    #    }

    constraint {
      attribute = "${node.unique.name}"
      value     = "ubuntu-02"
    }

    #    affinity {
    #      attribute = "${node.unique.name}"
    #      value     = "ubuntu-01"
    #      weight    = 75
    #    }

    vault {
      policies    = ["nomad-workloads", "paperless"]
      change_mode = "restart"
    }

    network {
      mode = "bridge"
      port "http" {
        to = var.paperless_port
      }
    }

    service {
      name = "paperless"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.paperless.rule=Host(`paperless.thenoisykeyboard.com`)",
        "traefik.http.routers.paperless.entrypoints=https",
        "traefik.http.routers.paperless.tls=true",
        "traefik.http.routers.paperless.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/api/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "paperless-consume" {
      type      = "host"
      source    = "paperless-consume"
      read_only = false
    }

    volume "paperless-data" {
      type      = "host"
      source    = "paperless-data"
      read_only = false
    }

    volume "paperless-export" {
      type      = "host"
      source    = "paperless-export"
      read_only = false
    }

    volume "paperless-media" {
      type      = "host"
      source    = "paperless-media"
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

    task "paperless" {
      driver = "docker"

      config {
        image        = var.paperless_image_tag
        ports        = ["http"]
        volumes      = ["/etc/localtime:/etc/localtime:ro"]
        security_opt = ["no-new-privileges"]
        shm_size     = 256
      }

      volume_mount {
        volume      = "paperless-consume"
        destination = "/usr/src/paperless/consume"
        read_only   = false
      }

      volume_mount {
        volume      = "paperless-data"
        destination = "/usr/src/paperless/data"
        read_only   = false
      }

      volume_mount {
        volume      = "paperless-export"
        destination = "/usr/src/paperless/export"
        read_only   = false
      }

      volume_mount {
        volume      = "paperless-media"
        destination = "/usr/src/paperless/media"
        read_only   = false
      }

      template {
        data        = <<-EOF
          {{ with secret "secret/data/paperless" }}
          {{ range $key, $value := .Data.data }}
          {{ $key }}={{ $value }}
          {{ end }}
          {{ end }}
      EOF
        destination = "secrets/paperless.env"
        env         = true
      }

      env { TZ = var.time_zone }

      resources {
        cpu    = var.paperless_cpu
        memory = var.paperless_memory
      }

      logs {
        max_files     = 1
        max_file_size = 10
        disabled      = false
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image   = var.redis_image_tag
        command = "redis-server"
        args = [
          "--appendonly", "no",
          "--save", "",
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
        max_file_size = 50
      }
    }
  }
}