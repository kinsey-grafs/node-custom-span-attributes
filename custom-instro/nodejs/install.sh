#!/bin/bash
set -euo pipefail

VERSION=0.2.1
docker build -t nodejs-autoinst:$VERSION .
kind load docker-image nodejs-autoinst:$VERSION

kubectl apply -f nodejs-override-instrumentation.yaml