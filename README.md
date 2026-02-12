# Node.js Custom Span Attributes with OpenTelemetry Operator

This repository demonstrates how to add **custom attributes to spans** when using the OpenTelemetry Operator's auto-instrumentation for Node.js applications.

## The Problem

The OpenTelemetry Operator provides zero-code auto-instrumentation via a simple annotation:

```yaml
instrumentation.opentelemetry.io/inject-nodejs: "true"
```

However, the default auto-instrumentation doesn't capture custom HTTP headers as span attributes. If you need to propagate business context (like `X-Client-Id`, `X-Request-Id`, or tenant identifiers) through your traces, you need to customize the instrumentation.

## The Solution

This repo shows how to:

1. Build a **custom auto-instrumentation image** that extends the default OTel Node.js image
2. Configure the HTTP instrumentation to capture specific headers as span attributes
3. Deploy an `Instrumentation` CR that uses your custom image

### Key Files

| File | Purpose |
|------|---------|
| `custom-instro/nodejs/register.js` | Custom instrumentation config that captures `X-Client-Id` header |
| `custom-instro/nodejs/Dockerfile` | Extends the official OTel image with custom config |
| `custom-instro/nodejs/nodejs-override-instrumentation.yaml` | Instrumentation CR using the custom image |
| `app/app.js` | Sample Node.js app that sets `X-Client-Id` response header |

### How Headers Become Span Attributes

The magic happens in `register.js`:

```javascript
const sdk = new opentelemetry.NodeSDK({
  instrumentations: getNodeAutoInstrumentations({
    "@opentelemetry/instrumentation-http": {
      headersToSpanAttributes: {
        client: {
          requestHeaders: ["X-Client-Id"],
          responseHeaders: ["X-Client-Id"],
        },
        server: {
          requestHeaders: ["X-Client-Id"],
          responseHeaders: ["X-Client-Id"],
        },
      },
    },
  }),
  // ...
});
```

This configuration tells the HTTP instrumentation to extract the `X-Client-Id` header and add it as a span attribute named `http.request.header.x-client-id` or `http.response.header.x-client-id`.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) (Kubernetes in Docker)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- A Grafana Cloud account (for metrics, logs, and traces)

## Quick Start

### 1. Configure Grafana Cloud Credentials

Get your credentials from the Grafana Cloud UI:
1. Go to **Connections** → **Add new connection** → **Alloy**
2. Follow the wizard - it will display all the usernames, passwords, and URLs for your stack

```bash
cd bootstrap
cp .env.example .env
# Edit .env with your Grafana Cloud credentials and URLs
```

The `.env` file requires:
- Prometheus, Loki, and OTLP usernames/passwords
- Endpoint URLs for your specific Grafana Cloud stack (these vary by region)

### 2. Run the Full Install

From the repo root:

```bash
./install.sh
```

This will:
1. Create a Kind cluster with port mapping
2. Install the Grafana k8s-monitoring stack (Alloy collectors)
3. Install the OpenTelemetry Operator
4. Build and deploy the custom instrumentation image
5. Deploy the sample Node.js application

### 3. Generate Telemetry

Once everything is running, send requests with the `X-Client-Id` header to generate traces with custom attributes:

```bash
# Single request with a custom client ID
curl http://localhost:8080 -H "X-Client-Id: my-test-client"

# Generate multiple requests with random client IDs
for i in {1..10}; do
  curl http://localhost:8080 -H "X-Client-Id: ${RANDOM}"
  sleep 1
done
```

### 4. View Traces in Grafana Cloud

1. Open your Grafana Cloud instance
2. Navigate to **Explore** → Select your **Traces** datasource
3. Search for traces from `nodejs-hello-world`
4. Open a trace and look for the span attribute: `http.response.header.x_client_id`

You should see the `X-Client-Id` value captured as a span attribute on the HTTP server spans.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Kind Cluster                            │
│                                                                 │
│  ┌─────────────────┐      ┌─────────────────────────────────┐  │
│  │  Node.js App    │      │  OpenTelemetry Operator         │  │
│  │  (with custom   │◄─────│  (injects auto-instrumentation) │  │
│  │   instro)       │      └─────────────────────────────────┘  │
│  └────────┬────────┘                                           │
│           │ OTLP                                                │
│           ▼                                                     │
│  ┌─────────────────┐                                           │
│  │  Grafana Alloy  │──────────────────────────────────────────►│ Grafana Cloud
│  │  (receiver)     │        traces, metrics, logs              │
│  └─────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

## Customizing for Your Headers

To capture different headers, modify `custom-instro/nodejs/register.js`:

```javascript
headersToSpanAttributes: {
  server: {
    requestHeaders: ["X-Client-Id", "X-Tenant-Id", "X-Request-Id"],
    responseHeaders: ["X-Client-Id"],
  },
},
```

Then rebuild and redeploy:

```bash
cd custom-instro/nodejs
./install.sh
kubectl rollout restart deployment/nodejs-hello-world
```

## Updating the Instrumentation Version

This repo pins the OpenTelemetry Node.js auto-instrumentation version. You should periodically update to get bug fixes, new instrumentation libraries, and performance improvements.

**Current version:** `0.69.0` (defined in `custom-instro/nodejs/Dockerfile`)

To update:

1. Check for the latest version at [opentelemetry-operator releases](https://github.com/open-telemetry/opentelemetry-operator/releases) or [Docker Hub](https://hub.docker.com/r/otel/autoinstrumentation-nodejs/tags)

2. Update the base image in `custom-instro/nodejs/Dockerfile`:

```dockerfile
FROM otel/autoinstrumentation-nodejs:0.71.0  # Update version here
```

3. Update the image tag in `custom-instro/nodejs/install.sh`:

```bash
VERSION=0.2.2  # Bump your custom image version
```

4. Rebuild and redeploy:

```bash
cd custom-instro/nodejs
./install.sh
kubectl rollout restart deployment/nodejs-hello-world
```

> **Note:** After major version updates, review the [opentelemetry-js changelog](https://github.com/open-telemetry/opentelemetry-js/blob/main/CHANGELOG.md) for any breaking changes to the `headersToSpanAttributes` API or other configuration options.

## Project Structure

```
.
├── bootstrap/              # Cluster setup and Grafana Cloud config
│   ├── cluster.yaml        # Kind cluster configuration
│   ├── install.sh          # Installs k8s-monitoring + OTel operator
│   ├── .env.example        # Template for Grafana Cloud credentials
│   └── .env                # Your credentials (gitignored)
├── custom-instro/
│   └── nodejs/             # Custom Node.js instrumentation image
│       ├── Dockerfile      # Extends official OTel image
│       ├── register.js     # Custom SDK configuration
│       ├── nodejs-override-instrumentation.yaml
│       └── install.sh
├── app/                    # Sample application
│   ├── app.js              # Simple HTTP server
│   ├── Dockerfile
│   ├── app-manifest.yaml   # K8s deployment with OTel annotation
│   └── install.sh
└── install.sh              # One-command full setup
```

## Adapting for Your Own Environment

This demo uses Kind for local development, but the pattern works in any Kubernetes cluster. Here's how to adapt it for your environment:

### Prerequisites

1. **OpenTelemetry Operator** installed in your cluster ([installation guide](https://github.com/open-telemetry/opentelemetry-operator#getting-started))
2. **A container registry** accessible from your cluster (ECR, GCR, ACR, Docker Hub, etc.)
3. **An OTLP endpoint** to receive traces (Grafana Cloud, Jaeger, or any OTLP-compatible backend)

### Step 1: Customize the Instrumentation Config

Edit `custom-instro/nodejs/register.js` to capture the headers you need:

```javascript
headersToSpanAttributes: {
  server: {
    requestHeaders: ["X-Tenant-Id", "X-Request-Id", "X-Correlation-Id"],
    responseHeaders: ["X-Request-Id"],
  },
  client: {
    requestHeaders: ["X-Tenant-Id"],
    responseHeaders: [],
  },
},
```

### Step 2: Build and Push the Custom Image

```bash
# Set your registry
REGISTRY="your-registry.example.com"
IMAGE_NAME="custom-nodejs-autoinstrumentation"
VERSION="1.0.0"

# Build the image
cd custom-instro/nodejs
docker build -t ${REGISTRY}/${IMAGE_NAME}:${VERSION} .

# Push to your registry
docker push ${REGISTRY}/${IMAGE_NAME}:${VERSION}
```

### Step 3: Deploy the Instrumentation CR

Create an `Instrumentation` resource pointing to your custom image and OTLP endpoint:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: custom-nodejs-instrumentation
  namespace: your-namespace  # or default
spec:
  exporter:
    # Point to your OTLP endpoint (examples below)
    # Grafana Alloy in-cluster:
    endpoint: http://alloy.monitoring.svc.cluster.local:4318
    # Or direct to Grafana Cloud (requires auth via env vars):
    # endpoint: https://otlp-gateway-prod-us-east-0.grafana.net:443
  propagators:
    - tracecontext
    - baggage
  nodejs:
    image: your-registry.example.com/custom-nodejs-autoinstrumentation:1.0.0
    env:
      - name: OTEL_TRACES_EXPORTER
        value: otlp
      # Add auth if sending directly to Grafana Cloud:
      # - name: OTEL_EXPORTER_OTLP_HEADERS
      #   value: "Authorization=Basic <base64-encoded-credentials>"
  sampler:
    type: parentbased_traceidratio
    argument: "1"  # 100% sampling, adjust for production
```

Apply it:

```bash
kubectl apply -f instrumentation.yaml
```

### Step 4: Annotate Your Deployments

Add the annotation to any Node.js deployment you want instrumented:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nodejs-app
spec:
  template:
    metadata:
      annotations:
        # Reference the Instrumentation CR by name
        instrumentation.opentelemetry.io/inject-nodejs: "true"
        # Or specify a specific Instrumentation CR:
        # instrumentation.opentelemetry.io/inject-nodejs: "custom-nodejs-instrumentation"
    spec:
      containers:
      - name: app
        image: my-app:latest
```

Restart your deployment to pick up the instrumentation:

```bash
kubectl rollout restart deployment/my-nodejs-app
```

### Step 5: Verify

Send a request with your custom header and check your tracing backend:

```bash
kubectl port-forward svc/my-nodejs-app 8080:80
curl http://localhost:8080 -H "X-Tenant-Id: customer-123"
```

You should see `http.request.header.x_tenant_id: customer-123` as a span attribute.

### Common OTLP Endpoint Configurations

| Backend | Endpoint Example |
|---------|------------------|
| Grafana Alloy (in-cluster) | `http://alloy.monitoring.svc.cluster.local:4318` |
| Grafana Cloud | `https://otlp-gateway-prod-us-east-0.grafana.net:443` |
| Jaeger | `http://jaeger-collector.tracing.svc.cluster.local:4318` |
| OpenTelemetry Collector | `http://otel-collector.monitoring.svc.cluster.local:4318` |

## Adding to an Existing Project

If you want to add custom span attributes to an existing Node.js project, here's exactly what to add to your repo.

### Files to Add

Create a directory in your project (e.g., `otel/nodejs-instrumentation/`) with these three files:

**1. `otel/nodejs-instrumentation/register.js`**

```javascript
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });

const opentelemetry = require("@opentelemetry/sdk-node");
const { diag, DiagConsoleLogger } = require("@opentelemetry/api");
const { getStringFromEnv, diagLogLevelFromString } = require("@opentelemetry/core");
const { getNodeAutoInstrumentations, getResourceDetectorsFromEnv } = require("./utils");

const logLevel = getStringFromEnv("OTEL_LOG_LEVEL");
if (logLevel != null) {
  diag.setLogger(new DiagConsoleLogger(), {
    logLevel: diagLogLevelFromString(logLevel),
  });
}

const sdk = new opentelemetry.NodeSDK({
  instrumentations: getNodeAutoInstrumentations({
    "@opentelemetry/instrumentation-http": {
      headersToSpanAttributes: {
        client: {
          requestHeaders: ["X-Client-Id", "X-Tenant-Id", "X-Request-Id"],  // Customize these
          responseHeaders: ["X-Client-Id"],
        },
        server: {
          requestHeaders: ["X-Client-Id", "X-Tenant-Id", "X-Request-Id"],  // Customize these
          responseHeaders: ["X-Client-Id"],
        },
      },
    },
  }),
  resourceDetectors: getResourceDetectorsFromEnv(),
});

try {
  sdk.start();
  diag.info("OpenTelemetry automatic instrumentation started successfully");
} catch (error) {
  diag.error(
    "Error initializing OpenTelemetry SDK. Your application is not instrumented and will not produce telemetry",
    error
  );
}

async function shutdown() {
  try {
    await sdk.shutdown();
    diag.debug("OpenTelemetry SDK terminated");
  } catch (error) {
    diag.error("Error terminating OpenTelemetry SDK", error);
  }
}

process.on("SIGTERM", shutdown);
process.once("beforeExit", shutdown);
```

**2. `otel/nodejs-instrumentation/Dockerfile`**

```dockerfile
FROM otel/autoinstrumentation-nodejs:0.69.0
COPY register.js /autoinstrumentation
COPY register.js /autoinstrumentation/autoinstrumentation.js
```

**3. `otel/nodejs-instrumentation/instrumentation.yaml`**

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: nodejs-custom-headers
spec:
  exporter:
    endpoint: http://your-otlp-endpoint:4318  # Update this
  propagators:
    - tracecontext
    - baggage
  nodejs:
    image: your-registry/nodejs-custom-instrumentation:1.0.0  # Update this
    env:
      - name: OTEL_TRACES_EXPORTER
        value: otlp
  sampler:
    type: parentbased_traceidratio
    argument: "1"
```

### Add to Your CI/CD Pipeline

Add a build step for the custom instrumentation image:

```yaml
# Example GitHub Actions step
- name: Build and push custom OTel instrumentation
  run: |
    docker build -t $REGISTRY/nodejs-custom-instrumentation:$VERSION ./otel/nodejs-instrumentation
    docker push $REGISTRY/nodejs-custom-instrumentation:$VERSION
```

### Update Your Kubernetes Manifests

Add the annotation to your existing deployment:

```yaml
# In your existing deployment.yaml
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-nodejs: "nodejs-custom-headers"
```

### Checklist

- [ ] Create `otel/nodejs-instrumentation/` directory with the three files above
- [ ] Customize the headers list in `register.js`
- [ ] Update the OTLP endpoint in `instrumentation.yaml`
- [ ] Update the image name/registry in `instrumentation.yaml`
- [ ] Add Docker build step to your CI/CD pipeline
- [ ] Add `kubectl apply -f otel/nodejs-instrumentation/instrumentation.yaml` to your deployment process
- [ ] Add the annotation to your app's Kubernetes manifests
- [ ] Restart your deployments

### Minimal File Structure

```
your-existing-project/
├── src/
├── package.json
├── Dockerfile
├── k8s/
│   └── deployment.yaml        # Add annotation here
└── otel/
    └── nodejs-instrumentation/
        ├── Dockerfile         # Builds custom instrumentation image
        ├── register.js        # Your header configuration
        └── instrumentation.yaml  # Kubernetes CR
```

## Cleanup

```bash
kind delete cluster
```

## References

- [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator)
- [Node.js HTTP Instrumentation Options](https://github.com/open-telemetry/opentelemetry-js/tree/main/experimental/packages/opentelemetry-instrumentation-http#http-instrumentation-options)
- [Grafana k8s-monitoring Helm Chart](https://github.com/grafana/k8s-monitoring-helm)
