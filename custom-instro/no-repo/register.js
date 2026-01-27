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