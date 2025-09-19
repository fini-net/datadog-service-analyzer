# datadog-service-analyzer

![GitHub Issues](https://img.shields.io/github/issues/fini-net/datadog-service-analyzer)
![GitHub Pull Requests](https://img.shields.io/github/issues-pr/fini-net/datadog-service-analyzer)
![GitHub License](https://img.shields.io/github/license/fini-net/datadog-service-analyzer)
![GitHub watchers](https://img.shields.io/github/watchers/fini-net/datadog-service-analyzer)

Which services in datadog are missing from service catalog?

## Status

✅ **Implemented!** The core functionality is ready to use.

## What This Does

Ever wonder if you've got services sending telemetry to Datadog that somehow
aren't registered in your [service catalog](https://docs.datadoghq.com/internal_developer_portal/software_catalog/)?
Yeah, me too. That's the gap this tool fills.

This analyzer digs through your Datadog telemetry data to identify services that
are actively sending metrics, traces, or logs but are mysteriously absent from
your service catalog. Think of it as a detective for your observability setup—
finding those orphaned services that are chattering away but nobody officially
knows they exist.

## Why You'd Want This

- **Service Discovery**: Uncover services you didn't know were running
- **Catalog Completeness**: Ensure your service catalog actually reflects reality
- **Compliance**: Meet those pesky requirements for complete service inventories
- **Operational Awareness**: Stop being surprised by services in production

## How It Works

The tool connects to your Datadog instance, pulls telemetry data across different
signal types (metrics, traces, logs), and cross-references against your service
catalog to identify the gaps. Simple concept, but surprisingly useful when you're
dealing with large, distributed systems where services tend to multiply like
rabbits.

## Prerequisites

Before running the analyzer, you'll need:

- **1Password CLI** (`op`) - for retrieving API credentials
- **curl** - for making API requests
- **jq** - for JSON processing

Install these on macOS with:

```bash
brew install 1password-cli curl jq
```

## Setup

1. Store your Datadog credentials in 1Password with these fields:
   - `api_key` - Your Datadog API key
   - `app_key` - Your Datadog application key
   - `site` - Your Datadog site (optional, defaults to `datadoghq.com`)

2. Make sure you're signed in to 1Password CLI:

```bash
op signin
```

## Usage

### Basic Usage

```bash
# Run with default settings (last 7 days, table output)
./datadog-service-analyzer.sh
```

### Command Line Options

```bash
./datadog-service-analyzer.sh [OPTIONS]

OPTIONS:
    -h, --help              Show help message
    -v, --verbose           Enable verbose output
    -o, --output FORMAT     Output format (json|table|csv) [default: table]
    --op-vault VAULT       1Password vault name [default: datadog]
    --op-item ITEM         1Password item name [default: datadog-api]
    --days DAYS            Days of telemetry data to analyze [default: 7]
```

### Service Analyzer Examples

```bash
# Analyze last 14 days with JSON output
./datadog-service-analyzer.sh --output json --days 14

# Use custom 1Password vault and item
./datadog-service-analyzer.sh --op-vault production --op-item datadog-prod

# CSV output for spreadsheet analysis
./datadog-service-analyzer.sh --output csv --days 30

# Verbose mode for troubleshooting
./datadog-service-analyzer.sh --verbose
```

### Team Mapper Examples

```bash
# Generate team mappings in JSON format (default)
./service-team-mapper.sh

# Table format for human reading
./service-team-mapper.sh --output table

# CSV format for spreadsheet import
./service-team-mapper.sh --output csv

# Use custom 1Password credentials
./service-team-mapper.sh --op-vault production --op-item datadog-prod
```

### Sample Output

#### Service Analyzer

**Table format (default):**

```text
=== Datadog Service Analyzer Results ===

Services found in telemetry: 42
Services in service catalog: 38
Services missing from catalog: 4

Missing services:
  - legacy-payment-processor
  - temp-migration-worker
  - experimental-ml-service
  - orphaned-batch-job
```

**JSON format:**

```json
{
  "summary": {
    "services_in_telemetry": 42,
    "services_in_catalog": 38,
    "missing_from_catalog": 4
  },
  "missing_services": [
    "legacy-payment-processor",
    "temp-migration-worker",
    "experimental-ml-service",
    "orphaned-batch-job"
  ]
}
```

#### Team Mapper

**JSON format (default):**

```json
{
  "summary": {
    "total_services": 25,
    "services_with_teams": 18,
    "services_with_org_units": 12
  },
  "services": [
    {
      "service": "payment-api",
      "team": "payments-team",
      "org_unit": "commerce",
      "description": "Handles payment processing",
      "links": [{"name": "repo", "url": "github.com/company/payment-api"}]
    },
    {
      "service": "user-service",
      "team": "identity-team",
      "org_unit": "platform",
      "description": "User management and authentication",
      "links": []
    }
  ]
}
```

**Table format:**

```text
=== Service Team Mappings ===

SERVICE                        TEAM                 ORG_UNIT        DESCRIPTION
------------------------------ -------------------- --------------- ------------------------------
payment-api                    payments-team        commerce        Handles payment processing
user-service                   identity-team        platform        User management and auth...
legacy-system                  N/A                  N/A             Legacy monolith service
```

## Available Scripts

### datadog-service-analyzer.sh

Analyzes Datadog telemetry to find services missing from service catalog.

**Features:**

- **Multi-signal Analysis**: Discovers services from metrics, APM traces, and logs
- **Service Catalog Cross-reference**: Compares discovered services against your service catalog
- **Configurable Time Range**: Analyze telemetry data from the last N days

### service-team-mapper.sh

Generates a list of services mapped to teams from the Datadog service catalog.

**Features:**

- **Team Mapping**: Extracts team contact information from service definitions
- **Organizational Structure**: Includes `org_unit` tags when present in service catalog
- **Service Metadata**: Includes descriptions and links for each service

## Common Features

- **1Password Integration**: Securely retrieves API credentials from 1Password
- **Flexible Output**: Supports table, JSON, and CSV output formats
- **Error Handling**: Robust error checking and informative error messages
- **ShellCheck Compliant**: Follows bash best practices

## Getting Started

This project uses [just](https://github.com/casey/just) for development workflow.
Run `just` to see available commands, or check out the
[development process](.github/CONTRIBUTING.md#development-process) for the full
workflow.

## Contributing Links

- [Code of Conduct](.github/CODE_OF_CONDUCT.md)
- [Contributing Guide](.github/CONTRIBUTING.md) includes a step-by-step guide to our
  [development processs](.github/CONTRIBUTING.md#development-process).

## Support & Security

- [Getting Support](.github/SUPPORT.md)
- [Security Policy](.github/SECURITY.md)
