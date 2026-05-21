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
# Analyze services missing from catalog (default: last 7 days, markdown output)
./datadog-service-analyzer.sh

# Generate service-to-team mappings (default: JSON output)
./service-team-mapper.sh

# Common options for both scripts:
# --output (json|table|csv)           # service-team-mapper.sh
# --output (json|table|markdown|csv)  # datadog-service-analyzer.sh
# --verbose
# --op-vault VAULT --op-item ITEM
# --days DAYS (service analyzer only)
```

### Quality checks

```bash
# ShellCheck on main scripts
shellcheck datadog-service-analyzer.sh
shellcheck service-team-mapper.sh

# ShellCheck on justfile recipe scripts (extracts and checks embedded bash)
just shellcheck

# Markdown linting
markdownlint-cli2 "**/*.md"
```

### Development workflow via justfile

The project uses [just](https://github.com/casey/just) for workflow automation:

```bash
just                         # List available commands
just compliance_check        # Repository compliance checks
just branch feature-name     # Create timestamped branch ($USER/$DATE-branchname)
just pr                      # Push, create PR (title from first commit), watch checks
just prweb                   # View PR in browser
just again                   # Push new commits, update PR description, watch checks
just merge                   # Squash-merge PR, cleanup, return to main
just sync                    # Return to main and pull latest
just release v1.2.3          # Create GitHub release with auto-generated notes
just release_age             # Check how long since last release
```

## Architecture

### Script structure

Both bash scripts follow this pattern:

1. Strict mode (`set -euo pipefail`)
2. Color-coded logging functions (`log_info`, `log_warn`, `log_error`, `log_success`)
3. Credential retrieval (env vars first, then 1Password via `op`)
4. API interactions with Datadog (metrics, APM, logs, service catalog)
5. Output formatting based on `--output` flag

### Key behaviors

- `datadog-service-analyzer.sh` exits 1 when missing services are found (not an error, a signal for CI/scripting)
- `normalize_service_names` strips trailing hex suffixes (e.g., `-a3f2b1`) to deduplicate dynamic service names
- Service catalog pagination uses `page[number]` (not `page[offset]`) and detects the end by checking for duplicate results rather than relying on page size, because the DD API returns full repeated pages past the end

### Credential management

Credentials are resolved in order: environment variables first, then 1Password.

**Environment variables** (standard Datadog names):

- `DD_API_KEY` - Datadog API key
- `DD_APP_KEY` - Datadog application key
- `DD_SITE` - Datadog site (optional, defaults to `datadoghq.com`)

**1Password fallback** (used when `DD_API_KEY`/`DD_APP_KEY` are not set):

Scripts expect 1Password items with these fields:

- `api_key` - Datadog API key
- `app_key` - Datadog application key
- `site` - Datadog site (optional, defaults to `datadoghq.com`)

Default vault: `datadog`, default item: `datadog-api`

### Justfile modules

The main `justfile` imports modules from `.just/`:

- `gh-process.just` - Git/GitHub workflow automation (branch/PR/merge cycle)
- `compliance.just` - Repository compliance checks
- `shellcheck.just` - ShellCheck linting on justfile recipe scripts
- `claude.just` - Claude Code permission management (`just claude_permissions_sort`, `just claude_permissions_check`)
- `repo-toml.just` - `.repo.toml` metadata generation/validation
- `copilot.just`, `pr-hook.just`, `template-sync.just`, `cue-verify.just`

### Feature flags (.repo.toml)

The `.repo.toml` file controls CI behavior via `[flags]`:

- `claude-review` - Enables Claude Code PR review in `just pr_checks`
- `copilot-review` - Enables Copilot PR review in `just pr_checks`
- `standard-release` - Enables `just release` workflow

## Development notes

- The project has no Python/JavaScript dependencies - it's pure bash + `jq` + `curl`
- ShellCheck compliance is enforced on both main scripts and justfile recipes
- Markdown linting config in `.markdownlint.yml` disables line-length (MD013) and first-line-heading (MD041)
