# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a bash-based toolset for analyzing Datadog telemetry and service catalog data. The main tools are:

- `datadog-service-analyzer.sh` - Identifies services sending telemetry to Datadog but missing from the service catalog
- `service-team-mapper.sh` - Maps services to their owning teams from the service catalog

Both scripts use 1Password CLI (`op`) for credential management and support multiple output formats (table, JSON, CSV).

## Core Commands

### Running the tools

```bash
# Analyze services missing from catalog (default: last 7 days, table output)
./datadog-service-analyzer.sh

# Generate service-to-team mappings (default: JSON output)
./service-team-mapper.sh

# Common options for both scripts:
# --output (json|table|csv)
# --verbose
# --op-vault VAULT --op-item ITEM
# --days DAYS (service analyzer only)
```

### Development workflow via justfile

The project uses [just](https://github.com/casey/just) for workflow automation:

```bash
# List available commands
just

# Compliance checks
just compliance_check

# Branch workflow
just branch feature-name     # Create timestamped branch
just pr                      # Create PR from last commit message, watch checks
just prweb                   # View PR in browser
just merge                   # Squash-merge PR, cleanup, return to main
just sync                    # Return to main and pull latest
```

### Quality checks

```bash
# ShellCheck (both scripts are compliant)
shellcheck datadog-service-analyzer.sh
shellcheck service-team-mapper.sh

# Markdown linting
markdownlint-cli2 "**/*.md"
```

## Architecture

### Script structure

Both bash scripts follow this pattern:

1. Strict mode (`set -euo pipefail`)
2. Color-coded logging functions (`log_info`, `log_warn`, `log_error`, `log_success`)
3. Credential retrieval from 1Password using `op read`
4. API interactions with Datadog (metrics, APM, logs, service catalog)
5. Output formatting based on `--output` flag

### Credential management

Scripts expect 1Password items with these fields:

- `api_key` - Datadog API key
- `app_key` - Datadog application key
- `site` - Datadog site (optional, defaults to `datadoghq.com`)

Default vault: `datadog`, default item: `datadog-api`

### Justfile imports

The main `justfile` imports two modules:

- `.just/compliance.just` - Repository compliance checks (README, LICENSE, CODE_OF_CONDUCT, etc.)
- `.just/gh-process.just` - Git/GitHub workflow automation (branch/PR/merge cycle)

The `gh-process.just` workflow creates branches with timestamps (`$USER/$DATE-branchname`) and uses the last commit message as the PR title.

## Development notes

- The project has no Python/JavaScript dependencies - it's pure bash
- Both scripts support the same 1Password authentication pattern
- Output formatting is consistent across tools (table/JSON/CSV)
- ShellCheck compliance is enforced
