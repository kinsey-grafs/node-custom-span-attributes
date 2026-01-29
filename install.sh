#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Setting up Kind cluster and Grafana k8s-monitoring..."
cd "$SCRIPT_DIR/bootstrap"
bash install.sh

echo "==> Waiting for cluster to stabilize..."
sleep 30

echo "==> Building and deploying custom instrumentation..."
cd "$SCRIPT_DIR/custom-instro/nodejs"
bash install.sh

echo "==> Waiting for instrumentation to be ready..."
sleep 5

echo "==> Building and deploying sample application..."
cd "$SCRIPT_DIR/app"
bash install.sh

echo ""
echo "==> Setup complete!"
echo "    Test with: curl http://localhost:8080 -H 'X-Client-Id: test-123'"
echo "    View traces in Grafana Cloud under Explore → Traces"
