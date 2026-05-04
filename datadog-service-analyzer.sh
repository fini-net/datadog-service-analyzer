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

count_lines() {
    if [[ -z "$1" ]]; then
        echo "0"
    else
        echo "$1" | wc -l | tr -d ' '
    fi
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

ENVIRONMENT VARIABLES:
    DD_API_KEY              Datadog API key (overrides 1Password)
    DD_APP_KEY              Datadog application key (overrides 1Password)
    DD_SITE                 Datadog site [default: datadoghq.com]

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --output json --days 14
    $SCRIPT_NAME --op-vault production --op-item datadog-prod
    DD_API_KEY=xxx DD_APP_KEY=yyy $SCRIPT_NAME

EOF
}

check_dependencies() {
    local need_op="$1"
    local missing_deps=()

    if [[ "$need_op" == "true" ]] && ! command -v op &> /dev/null; then
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
        if [[ "$need_op" == "true" ]]; then
            log_info "Alternatively, set DD_API_KEY and DD_APP_KEY environment variables to skip 1Password"
        fi
        exit 1
    fi
}

get_credentials_from_env() {
    { local restore_trace=false; [[ $- == *x* ]] && restore_trace=true; set +x; } 2>/dev/null
    if [[ -n "${DD_API_KEY:-}" && -n "${DD_APP_KEY:-}" ]]; then
        if [[ "${DD_API_KEY}" == *"|"* || "${DD_APP_KEY}" == *"|"* ]]; then
            log_error "DD_API_KEY and DD_APP_KEY must not contain '|'"
            exit 1
        fi
        local site="${DD_SITE:-datadoghq.com}"
        log_info "Using credentials from environment variables"
        echo "${DD_API_KEY}|${DD_APP_KEY}|${site}"
        { [[ "$restore_trace" == "true" ]] && set -x; } 2>/dev/null
        return 0
    elif [[ -n "${DD_API_KEY:-}" || -n "${DD_APP_KEY:-}" ]]; then
        log_warn "Only one of DD_API_KEY/DD_APP_KEY is set — both required to skip 1Password. Falling back to 1Password."
    fi
    { [[ "$restore_trace" == "true" ]] && set -x; } 2>/dev/null
    return 1
}

get_credentials_from_1password() {
    { local restore_trace=false; [[ $- == *x* ]] && restore_trace=true; set +x; } 2>/dev/null
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
    { [[ "$restore_trace" == "true" ]] && set -x; } 2>/dev/null
}

make_datadog_request() {
    local endpoint="$1"
    local api_key="$2"
    local app_key="$3"
    local site="$4"
    local method="${5:-GET}"
    local body="${6:-}"

    local url="https://api.${site}${endpoint}"

    local -a curl_args=(-s
        -H "DD-API-KEY: $api_key"
        -H "DD-APPLICATION-KEY: $app_key"
        -H "Content-Type: application/json"
        -X "$method"
    )

    if [[ -n "$body" ]]; then
        curl_args+=(-d "$body")
    fi

    curl "${curl_args[@]}" "$url"
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

    log_info "Checking APM traces for service names..."
    local apm_env="*"
    local apm_response
    apm_response=$(make_datadog_request \
        "/api/v1/service_dependencies?start=$start_time&end=$end_time&env=$apm_env" \
        "$api_key" "$app_key" "$site")

    if [[ -n "$apm_response" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && services+=("$line")
        done < <(echo "$apm_response" | jq -r 'keys[]?' 2>/dev/null | sort -u)
    fi

    log_info "Checking metrics for service tags..."
    local metrics_response
    metrics_response=$(make_datadog_request \
        "/api/v1/tags/hosts" \
        "$api_key" "$app_key" "$site")

    if [[ -n "$metrics_response" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && services+=("$line")
        done < <(echo "$metrics_response" | jq -r '
            .tags | to_entries[]? |
            select(.key | startswith("service:")) |
            .key | sub("^service:"; "")' 2>/dev/null | sort -u)
    fi

    log_info "Checking logs for service names..."
    local from_iso to_iso
    from_iso=$(date -u -d "@$start_time" '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null \
        || date -u -r "$start_time" '+%Y-%m-%dT%H:%M:%S.000Z')
    to_iso=$(date -u -d "@$end_time" '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null \
        || date -u -r "$end_time" '+%Y-%m-%dT%H:%M:%S.000Z')
    local logs_body
    logs_body=$(jq -n \
        --arg from "$from_iso" \
        --arg to "$to_iso" \
        '{
            filter: { query: "*", from: $from, to: $to },
            group_by: [{ facet: "service", limit: 10000 }],
            compute: [{ aggregation: "count" }]
        }')
    local logs_response
    logs_response=$(make_datadog_request \
        "/api/v2/logs/analytics/aggregate" \
        "$api_key" "$app_key" "$site" "POST" "$logs_body")

    if [[ -n "$logs_response" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && services+=("$line")
        done < <(echo "$logs_response" | jq -r '
            .data.buckets[]? |
            .by.service // empty' 2>/dev/null | sort -u)
    fi

    if [[ ${#services[@]} -gt 0 ]]; then
        printf '%s\n' "${services[@]}" | sort -u | grep -v '^$' || true
    fi
}

get_service_catalog() {
    local api_key="$1"
    local app_key="$2"
    local site="$3"

    log_info "Retrieving service catalog (paginated)"

    local page_size=200
    local page_offset=0
    local all_services=""
    local unique_before=0

    while true; do
        local catalog_response
        catalog_response=$(make_datadog_request \
            "/api/v2/services/definitions?page%5Bsize%5D=$page_size&page%5Boffset%5D=$page_offset&schema_version=v2.1" \
            "$api_key" "$app_key" "$site")

        if [[ -z "$catalog_response" ]]; then
            break
        fi

        local data_count
        data_count=$(echo "$catalog_response" | jq '.data | length' 2>/dev/null || echo "0")

        if [[ "$data_count" -eq 0 ]]; then
            break
        fi

        local page_services
        page_services=$(echo "$catalog_response" | jq -r '.data[]? | .attributes.schema."dd-service" // .attributes.schema.info["dd-service"] // empty' 2>/dev/null)

        if [[ -n "$page_services" ]]; then
            if [[ -n "$all_services" ]]; then
                all_services="$all_services"$'\n'"$page_services"
            else
                all_services="$page_services"
            fi
        fi

        local unique_now
        unique_now=$(echo "$all_services" | sort -u | grep -c -v '^$' || true)

        # DD catalog API returns full pages of repeated data past the end instead of short/empty pages
        if [[ "$unique_now" -eq "$unique_before" ]]; then
            log_info "No new services found on this page, stopping pagination"
            break
        fi
        unique_before=$unique_now

        if [[ "$data_count" -lt "$page_size" ]]; then
            break
        fi

        page_offset=$((page_offset + 1))
        log_info "Fetched $page_offset catalog entries so far (${unique_now} unique services)..."
    done

    if [[ -n "$all_services" ]]; then
        echo "$all_services" | sort -u | grep -v '^$'
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
    
    local total_missing
    total_missing=$(count_lines "$missing_services")

    case "$format" in
        json)
            cat << EOF
{
  "summary": {
    "services_in_telemetry": $total_telemetry,
    "services_in_catalog": $total_catalog,
    "missing_from_catalog": $total_missing
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
            echo "Services missing from catalog: $total_missing"
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

    local credentials
    if credentials=$(get_credentials_from_env); then
        check_dependencies false
    else
        check_dependencies true
        credentials=$(get_credentials_from_1password "$op_vault" "$op_item")
    fi

    { local _xt=false; [[ $- == *x* ]] && _xt=true; set +x; } 2>/dev/null
    IFS='|' read -r api_key app_key site <<< "$credentials"
    { [[ "$_xt" == "true" ]] && set -x; } 2>/dev/null
    
    local telemetry_services
    telemetry_services=$(get_services_from_telemetry "$api_key" "$app_key" "$site" "$days")
    
    local catalog_services
    catalog_services=$(get_service_catalog "$api_key" "$app_key" "$site")
    
    local missing_services
    missing_services=$(find_missing_services "$telemetry_services" "$catalog_services")
    
    local total_telemetry
    total_telemetry=$(count_lines "$telemetry_services")

    local total_catalog
    total_catalog=$(count_lines "$catalog_services")
    
    format_output "$output_format" "$missing_services" "$total_telemetry" "$total_catalog"
    
    if [[ -n "$missing_services" ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi