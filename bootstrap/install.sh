#!/bin/bash
set -euo pipefail

# Load secrets from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
else
  echo "ERROR: .env file not found at $SCRIPT_DIR/.env"
  echo "Copy .env.example to .env and fill in your Grafana Cloud credentials."
  exit 1
fi

# Validate required environment variables
required_vars=(
  "GRAFANA_PROM_USERNAME" "GRAFANA_PROM_PASSWORD" "GRAFANA_PROM_URL"
  "GRAFANA_LOKI_USERNAME" "GRAFANA_LOKI_PASSWORD" "GRAFANA_LOKI_URL"
  "GRAFANA_OTLP_USERNAME" "GRAFANA_OTLP_PASSWORD" "GRAFANA_OTLP_URL" "GRAFANA_FLEET_URL"
)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set"
    exit 1
  fi
done

kind create cluster --config cluster.yaml

# Install Grafana k8s-monitoring stack
# Configuration based on Grafana Cloud UI: Connections → Add new connection → Kubernetes
helm repo add grafana https://grafana.github.io/helm-charts &&
  helm repo update &&
  helm upgrade --install --timeout 300s grafana-k8s-monitoring grafana/k8s-monitoring \
    --namespace "default" --create-namespace --values - <<EOF
cluster:
  name: kind-kind
destinations:
  - name: grafana-cloud-metrics
    type: prometheus
    url: ${GRAFANA_PROM_URL}/api/prom/push
    auth:
      type: basic
      username: "${GRAFANA_PROM_USERNAME}"
      password: ${GRAFANA_PROM_PASSWORD}
  - name: grafana-cloud-logs
    type: loki
    url: ${GRAFANA_LOKI_URL}/loki/api/v1/push
    auth:
      type: basic
      username: "${GRAFANA_LOKI_USERNAME}"
      password: ${GRAFANA_LOKI_PASSWORD}
  - name: gc-otlp-endpoint
    type: otlp
    url: ${GRAFANA_OTLP_URL}/otlp
    protocol: http
    auth:
      type: basic
      username: "${GRAFANA_OTLP_USERNAME}"
      password: ${GRAFANA_OTLP_PASSWORD}
    metrics:
      enabled: true
    logs:
      enabled: true
    traces:
      enabled: true
clusterMetrics:
  enabled: true
  opencost:
    enabled: true
    metricsSource: grafana-cloud-metrics
    opencost:
      exporter:
        defaultClusterId: kind-kind
      prometheus:
        existingSecretName: grafana-cloud-metrics-grafana-k8s-monitoring
        external:
          url: ${GRAFANA_PROM_URL}/api/prom
  kepler:
    enabled: true
clusterEvents:
  enabled: true
podLogs:
  enabled: true
applicationObservability:
  enabled: true
  receivers:
    otlp:
      grpc:
        enabled: true
        port: 4317
      http:
        enabled: true
        port: 4318
    zipkin:
      enabled: true
      port: 9411
alloy-metrics:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: alloy-metrics-remote-cfg-grafana-k8s-monitoring
            key: password
      - name: CLUSTER_NAME
        value: kind-kind
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-\$(POD_NAME)
  remoteConfig:
    enabled: true
    url: ${GRAFANA_FLEET_URL}
    auth:
      type: basic
      username: "${GRAFANA_OTLP_USERNAME}"
      password: ${GRAFANA_OTLP_PASSWORD}
alloy-singleton:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: alloy-singleton-remote-cfg-grafana-k8s-monitoring
            key: password
      - name: CLUSTER_NAME
        value: kind-kind
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-\$(POD_NAME)
  remoteConfig:
    enabled: true
    url: ${GRAFANA_FLEET_URL}
    auth:
      type: basic
      username: "${GRAFANA_OTLP_USERNAME}"
      password: ${GRAFANA_OTLP_PASSWORD}
alloy-logs:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: alloy-logs-remote-cfg-grafana-k8s-monitoring
            key: password
      - name: CLUSTER_NAME
        value: kind-kind
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: NODE_NAME
        valueFrom:
          fieldRef:
            fieldPath: spec.nodeName
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-alloy-logs-\$(NODE_NAME)
  remoteConfig:
    enabled: true
    url: ${GRAFANA_FLEET_URL}
    auth:
      type: basic
      username: "${GRAFANA_OTLP_USERNAME}"
      password: ${GRAFANA_OTLP_PASSWORD}
alloy-receiver:
  enabled: true
  alloy:
    extraPorts:
      - name: otlp-grpc
        port: 4317
        targetPort: 4317
        protocol: TCP
      - name: otlp-http
        port: 4318
        targetPort: 4318
        protocol: TCP
      - name: zipkin
        port: 9411
        targetPort: 9411
        protocol: TCP
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: alloy-receiver-remote-cfg-grafana-k8s-monitoring
            key: password
      - name: CLUSTER_NAME
        value: kind-kind
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: NODE_NAME
        valueFrom:
          fieldRef:
            fieldPath: spec.nodeName
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-alloy-receiver-\$(NODE_NAME)
  remoteConfig:
    enabled: true
    url: ${GRAFANA_FLEET_URL}
    auth:
      type: basic
      username: "${GRAFANA_OTLP_USERNAME}"
      password: ${GRAFANA_OTLP_PASSWORD}
EOF

# Install OpenTelemetry Operator
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts &&
  helm repo update &&
  helm install my-opentelemetry-operator open-telemetry/opentelemetry-operator \
    --set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s" \
    --set admissionWebhooks.certManager.enabled=false \
    --set admissionWebhooks.autoGenerateCert.enabled=true
