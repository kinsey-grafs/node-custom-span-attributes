#!/bin/bash
set -euo pipefail

docker build -t demo-nodejs-app:latest .
kind load docker-image demo-nodejs-app:latest
kubectl apply -f app-manifest.yaml