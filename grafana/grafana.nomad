variables {
  deployer   = "Troy Rippin"
  datacenter = ["homelab"]
  version    = "1.0.0"
  team       = "platform"

  time_zone       = "Europe/Stockholm"
  image_tag       = "docker.io/grafana/grafana:latest"
  server_ip       = "10.1.1.11"
  grafana_port    = 3000
  loki_port       = 3100
  influxdb_port   = 8086
  prometheus_port = 9090

  cpu    = 500
  memory = 512
}

job "grafana" {

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

  group "grafana" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "ubuntu-03"
    }

    vault {
      policies    = ["nomad-workloads", "influxdb"]
      change_mode = "restart"
    }

    network {
      mode = "bridge"
      port "http" {
        to = var.grafana_port
      }
    }

    service {
      name = "grafana"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.grafana.rule=Host(`grafana-cluster.thenoisykeyboard.com`)",
        "traefik.http.routers.grafana.entrypoints=https",
        "traefik.http.routers.grafana.tls=true",
        "traefik.http.routers.grafana.middlewares=internal-only@file",
      ]

      check {
        type     = "http"
        path     = "/api/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "grafana" {
      type      = "host"
      source    = "grafana"
      read_only = false
    }

    volume "grafana-data" {
      type      = "host"
      source    = "grafana-data"
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

    task "grafana" {
      driver = "docker"

      config {
        image          = var.image_tag
        ports          = ["http"]
        volumes        = ["/etc/localtime:/etc/localtime:ro"]
        security_opt   = ["no-new-privileges:true"]
        auth_soft_fail = true
      }

      volume_mount {
        volume      = "grafana"
        destination = "/etc/grafana"
        read_only   = false
      }

      volume_mount {
        volume      = "grafana-data"
        destination = "/var/lib/grafana"
        read_only   = false
      }

      template {
        data        = <<-EOF
          apiVersion: 1
          datasources:
            - name: Prometheus
              type: prometheus
              orgId: 1
              uid: prometheus
              url: http://${var.server_ip}:${var.prometheus_port}
              editable: true
              isDefault: true
          
            - name: Loki
              type: loki
              orgId: 1
              uid: loki
              url: http://${var.server_ip}:${var.loki_port}
              editable: true
          
            - name: InfluxDB
              type: influxdb
              orgId: 1
              uid: influxdb
              url: http://${var.server_ip}:${var.influxdb_port}
              editable: true
              jsonData:
                version: Flux
                organization: homelab
                defaultBucket: docker
                tlsSkipVerify: true
              secureJsonData:
                token: {{ with secret "secret/data/influxdb" }}{{ .Data.data.token }}{{ end }}
        EOF
        destination = "local/provisioning/datasources/datasources.yaml"
        change_mode = "restart"
      }

      template {
        data        = <<-EOF
          apiVersion: 1
          providers:
            - name: "default"
              orgId: 1
              folder: ""
              type: file
              disableDeletion: false
              updateIntervalSeconds: 10
              options:
                path: /etc/grafana/dashboards
        EOF
        destination = "local/provisioning/dashboards/dashboards.yaml"
        change_mode = "restart"
      }

      template {
        data        = <<-EOF
          ##################### Grafana Configuration #####################

          [paths]
          provisioning = /local/provisioning

          [server]
          http_port = ${var.grafana_port}

          [analytics]
          check_for_updates = false
          check_for_plugin_updates = false

          [security]
          disable_initial_admin_creation = true
          disable_gravatar = true

          [dashboards]
          default_home_dashboard_path = "/etc/grafana/dashboards/node-exporter.json"

          [users]
          allow_sign_up = false
          default_theme = system
          default_language = en-GB

          [auth]
          disable_login_form = true

          [auth.anonymous]
          enabled = true
          org_role = Admin

          [auth.basic]
          enabled = false
        EOF
        destination = "local/grafana.ini"
        change_mode = "restart"
      }

      env {
        TZ                    = var.time_zone
        GF_SERVER_HTTP_PORT   = var.grafana_port
        GF_PATHS_CONFIG       = "/local/grafana.ini"
        GF_PATHS_PROVISIONING = "/local/provisioning"
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