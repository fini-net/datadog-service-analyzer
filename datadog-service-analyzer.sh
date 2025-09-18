#!/bin/bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Analyzes Datadog telemetry to find services missing from service catalog.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -o, --output FORMAT     Output format (json|table|csv) [default: table]
    --op-vault VAULT       1Password vault name [default: datadog]
    --op-item ITEM         1Password item name [default: datadog-api]
    --days DAYS            Days of telemetry data to analyze [default: 7]

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --output json --days 14
    $SCRIPT_NAME --op-vault production --op-item datadog-prod

EOF
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v op &> /dev/null; then
        missing_deps+=("1Password CLI (op)")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies:"
        printf '  - %s\n' "${missing_deps[@]}" >&2
        exit 1
    fi
}

get_credentials_from_1password() {
    local vault="${1:-datadog}"
    local item="${2:-datadog-api}"
    
    log_info "Retrieving credentials from 1Password vault: $vault, item: $item"
    
    if ! op vault get "$vault" &>/dev/null; then
        log_error "Cannot access 1Password vault: $vault"
        exit 1
    fi
    
    local api_key
    local app_key
    local site
    
    api_key=$(op item get "$item" --vault "$vault" --field "api_key" 2>/dev/null || {
        log_error "Failed to retrieve api_key from 1Password"
        exit 1
    })
    
    app_key=$(op item get "$item" --vault "$vault" --field "app_key" 2>/dev/null || {
        log_error "Failed to retrieve app_key from 1Password"
        exit 1
    })
    
    site=$(op item get "$item" --vault "$vault" --field "site" 2>/dev/null || echo "datadoghq.com")
    
    echo "$api_key|$app_key|$site"
}

make_datadog_request() {
    local endpoint="$1"
    local api_key="$2"
    local app_key="$3"
    local site="$4"
    
    local url="https://api.${site}/api/v1${endpoint}"
    
    curl -s \
        -H "DD-API-KEY: $api_key" \
        -H "DD-APPLICATION-KEY: $app_key" \
        -H "Content-Type: application/json" \
        "$url"
}

get_services_from_telemetry() {
    local api_key="$1"
    local app_key="$2"
    local site="$3"
    local days="$4"
    
    log_info "Discovering services from telemetry data (last $days days)"
    
    local end_time
    end_time=$(date +%s)
    local start_time=$((end_time - (days * 86400)))
    
    local services=()
    
    log_info "Checking metrics for service names..."
    local metrics_response
    metrics_response=$(make_datadog_request \
        "/query?query=*&from=$start_time&to=$end_time" \
        "$api_key" "$app_key" "$site")
    
    if [[ -n "$metrics_response" ]]; then
        readarray -t metric_services < <(echo "$metrics_response" | jq -r '
            .series[]? | 
            select(.metric | test("service:")) |
            .tags[]? | 
            select(test("^service:")) | 
            sub("^service:"; "")' 2>/dev/null | sort -u)
        services+=("${metric_services[@]}")
    fi
    
    log_info "Checking APM traces for service names..."
    local apm_response
    apm_response=$(make_datadog_request \
        "/apm/services?start=$start_time&end=$end_time" \
        "$api_key" "$app_key" "$site")
    
    if [[ -n "$apm_response" ]]; then
        readarray -t apm_services < <(echo "$apm_response" | jq -r '
            .[]? | select(.name) | .name' 2>/dev/null | sort -u)
        services+=("${apm_services[@]}")
    fi
    
    log_info "Checking logs for service names..."
    local logs_query="*"
    local logs_response
    logs_response=$(make_datadog_request \
        "/logs-queries/list?query=$logs_query&time.from=${start_time}000&time.to=${end_time}000&limit=1000" \
        "$api_key" "$app_key" "$site")
    
    if [[ -n "$logs_response" ]]; then
        readarray -t log_services < <(echo "$logs_response" | jq -r '
            .logs[]? | 
            .attributes.tags[]? | 
            select(test("^service:")) | 
            sub("^service:"; "")' 2>/dev/null | sort -u)
        services+=("${log_services[@]}")
    fi
    
    printf '%s\n' "${services[@]}" | sort -u | grep -v '^$'
}

get_service_catalog() {
    local api_key="$1"
    local app_key="$2"
    local site="$3"
    
    log_info "Retrieving service catalog"
    
    local catalog_response
    catalog_response=$(make_datadog_request \
        "/service-definitions" \
        "$api_key" "$app_key" "$site")
    
    if [[ -n "$catalog_response" ]]; then
        echo "$catalog_response" | jq -r '.data[]? | .attributes.service' 2>/dev/null | sort -u
    fi
}

find_missing_services() {
    local telemetry_services="$1"
    local catalog_services="$2"
    
    log_info "Analyzing service gaps..."
    
    comm -23 <(echo "$telemetry_services" | sort) <(echo "$catalog_services" | sort)
}

format_output() {
    local format="$1"
    local missing_services="$2"
    local total_telemetry="$3"
    local total_catalog="$4"
    
    case "$format" in
        json)
            cat << EOF
{
  "summary": {
    "services_in_telemetry": $total_telemetry,
    "services_in_catalog": $total_catalog,
    "missing_from_catalog": $(echo "$missing_services" | wc -l | tr -d ' ')
  },
  "missing_services": [
$(echo "$missing_services" | sed 's/^/    "/' | sed 's/$/"/' | sed '$!s/$/,/')
  ]
}
EOF
            ;;
        csv)
            echo "service_name,status"
            while IFS= read -r service; do
                echo "$service,missing_from_catalog"
            done <<< "$missing_services"
            ;;
        table|*)
            echo
            echo "=== Datadog Service Analyzer Results ==="
            echo
            echo "Services found in telemetry: $total_telemetry"
            echo "Services in service catalog: $total_catalog"
            echo "Services missing from catalog: $(echo "$missing_services" | wc -l | tr -d ' ')"
            echo
            if [[ -n "$missing_services" ]]; then
                echo "Missing services:"
                while IFS= read -r service; do
                    echo "  - $service"
                done <<< "$missing_services"
            else
                echo "✅ All services found in telemetry are registered in the service catalog!"
            fi
            echo
            ;;
    esac
}

main() {
    local verbose=false
    local output_format="table"
    local op_vault="datadog"
    local op_item="datadog-api"
    local days=7
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -o|--output)
                output_format="$2"
                shift 2
                ;;
            --op-vault)
                op_vault="$2"
                shift 2
                ;;
            --op-item)
                op_item="$2"
                shift 2
                ;;
            --days)
                days="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ "$verbose" == "true" ]]; then
        set -x
    fi
    
    check_dependencies
    
    local credentials
    credentials=$(get_credentials_from_1password "$op_vault" "$op_item")
    
    IFS='|' read -r api_key app_key site <<< "$credentials"
    
    local telemetry_services
    telemetry_services=$(get_services_from_telemetry "$api_key" "$app_key" "$site" "$days")
    
    local catalog_services
    catalog_services=$(get_service_catalog "$api_key" "$app_key" "$site")
    
    local missing_services
    missing_services=$(find_missing_services "$telemetry_services" "$catalog_services")
    
    local total_telemetry
    total_telemetry=$(echo "$telemetry_services" | wc -l | tr -d ' ')
    
    local total_catalog
    total_catalog=$(echo "$catalog_services" | wc -l | tr -d ' ')
    
    format_output "$output_format" "$missing_services" "$total_telemetry" "$total_catalog"
    
    if [[ -n "$missing_services" ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi