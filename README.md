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
| `custom-instro/no-repo/register.js` | Custom instrumentation config that captures `X-Client-Id` header |
| `custom-instro/no-repo/Dockerfile` | Extends the official OTel image with custom config |
| `custom-instro/no-repo/nodejs-override-instrumentation.yaml` | Instrumentation CR using the custom image |
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

To capture different headers, modify `custom-instro/no-repo/register.js`:

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
cd custom-instro/no-repo
./install.sh
kubectl rollout restart deployment/nodejs-hello-world
```

## Updating the Instrumentation Version

This repo pins the OpenTelemetry Node.js auto-instrumentation version. You should periodically update to get bug fixes, new instrumentation libraries, and performance improvements.

**Current version:** `0.69.0` (defined in `custom-instro/no-repo/Dockerfile`)

To update:

1. Check for the latest version at [opentelemetry-operator releases](https://github.com/open-telemetry/opentelemetry-operator/releases) or [Docker Hub](https://hub.docker.com/r/otel/autoinstrumentation-nodejs/tags)

2. Update the base image in `custom-instro/no-repo/Dockerfile`:

```dockerfile
FROM otel/autoinstrumentation-nodejs:0.71.0  # Update version here
```

3. Update the image tag in `custom-instro/no-repo/install.sh`:

```bash
VERSION=0.2.2  # Bump your custom image version
```

4. Rebuild and redeploy:

```bash
cd custom-instro/no-repo
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
│   └── no-repo/            # Custom instrumentation image
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

## Cleanup

```bash
kind delete cluster
```

## References

- [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator)
- [Node.js HTTP Instrumentation Options](https://github.com/open-telemetry/opentelemetry-js/tree/main/experimental/packages/opentelemetry-instrumentation-http#http-instrumentation-options)
- [Grafana k8s-monitoring Helm Chart](https://github.com/grafana/k8s-monitoring-helm)
