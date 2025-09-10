# datadog-service-analyzer

![GitHub Issues](https://img.shields.io/github/issues/fini-net/datadog-service-analyzer)
![GitHub Pull Requests](https://img.shields.io/github/issues-pr/fini-net/datadog-service-analyzer)
![GitHub License](https://img.shields.io/github/license/fini-net/datadog-service-analyzer)
![GitHub watchers](https://img.shields.io/github/watchers/fini-net/datadog-service-analyzer)

Which services in datadog are missing from service catalog?

## Status

This is only at the **idea** stage.  We'll see how life goes and whether
I get the time to actually implement this.

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
