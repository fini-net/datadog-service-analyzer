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

Generates a list of services mapped to teams from Datadog service catalog.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -o, --output FORMAT     Output format (json|table|csv) [default: json]
    --op-vault VAULT       1Password vault name [default: datadog]
    --op-item ITEM         1Password item name [default: datadog-api]

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --output table
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
    
    local url="https://api.${site}/api/v2${endpoint}"
    
    curl -s \
        -H "DD-API-KEY: $api_key" \
        -H "DD-APPLICATION-KEY: $app_key" \
        -H "Content-Type: application/json" \
        "$url"
}

get_service_team_mappings() {
    local api_key="$1"
    local app_key="$2"
    local site="$3"
    
    log_info "Retrieving service catalog with team mappings"
    
    local catalog_response
    catalog_response=$(make_datadog_request \
        "/services/definitions" \
        "$api_key" "$app_key" "$site")
    
    if [[ -z "$catalog_response" ]]; then
        log_error "Failed to retrieve service catalog"
        exit 1
    fi
    
    echo "$catalog_response" | jq -r '
        .data[]? |
        {
            service: .attributes.name,
            team: (.attributes.contacts[]? | select(.type == "team") | .contact),
            org_unit: (.attributes.tags[]? | select(startswith("org_unit:")) | sub("^org_unit:"; "")),
            description: .attributes.description,
            links: (.attributes.links[]? | {name: .name, url: .url})
        } |
        select(.service != null)
    ' 2>/dev/null | jq -s '
        map(
            . as $service |
            if .team then
                {
                    service: .service,
                    team: .team,
                    org_unit: (.org_unit // null),
                    description: (.description // null),
                    links: ([.links] | map(select(. != null)))
                }
            else
                {
                    service: .service,
                    team: null,
                    org_unit: (.org_unit // null),
                    description: (.description // null),
                    links: ([.links] | map(select(. != null)))
                }
            end
        ) |
        sort_by(.service)
    '
}

format_output() {
    local format="$1"
    local mappings="$2"
    
    case "$format" in
        table)
            echo
            echo "=== Service Team Mappings ==="
            echo
            printf "%-30s %-20s %-15s %s\n" "SERVICE" "TEAM" "ORG_UNIT" "DESCRIPTION"
            printf "%-30s %-20s %-15s %s\n" "$(printf '%30s' '' | tr ' ' '-')" "$(printf '%20s' '' | tr ' ' '-')" "$(printf '%15s' '' | tr ' ' '-')" "$(printf '%30s' '' | tr ' ' '-')"
            
            echo "$mappings" | jq -r '
                .[] |
                [
                    .service,
                    (.team // "N/A"),
                    (.org_unit // "N/A"),
                    ((.description // "N/A") | if length > 30 then .[0:27] + "..." else . end)
                ] |
                @tsv
            ' | while IFS=$'\t' read -r service team org_unit description; do
                printf "%-30s %-20s %-15s %s\n" "$service" "$team" "$org_unit" "$description"
            done
            
            echo
            local total_services
            total_services=$(echo "$mappings" | jq '. | length')
            local services_with_teams
            services_with_teams=$(echo "$mappings" | jq '[.[] | select(.team != null)] | length')
            local services_with_org_units
            services_with_org_units=$(echo "$mappings" | jq '[.[] | select(.org_unit != null)] | length')
            
            echo "Summary:"
            echo "  Total services: $total_services"
            echo "  Services with teams: $services_with_teams"
            echo "  Services with org_units: $services_with_org_units"
            echo
            ;;
        csv)
            echo "service,team,org_unit,description"
            echo "$mappings" | jq -r '
                .[] |
                [
                    .service,
                    (.team // ""),
                    (.org_unit // ""),
                    (.description // "")
                ] |
                @csv
            '
            ;;
        json|*)
            echo "$mappings" | jq '
                {
                    summary: {
                        total_services: length,
                        services_with_teams: [.[] | select(.team != null)] | length,
                        services_with_org_units: [.[] | select(.org_unit != null)] | length
                    },
                    services: .
                }
            '
            ;;
    esac
}

main() {
    local verbose=false
    local output_format="json"
    local op_vault="datadog"
    local op_item="datadog-api"
    
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
    
    local mappings
    mappings=$(get_service_team_mappings "$api_key" "$app_key" "$site")
    
    if [[ -z "$mappings" || "$mappings" == "[]" ]]; then
        log_warn "No services found in service catalog"
        case "$output_format" in
            json)
                echo '{"summary": {"total_services": 0, "services_with_teams": 0, "services_with_org_units": 0}, "services": []}'
                ;;
            *)
                echo "No services found."
                ;;
        esac
        exit 0
    fi
    
    format_output "$output_format" "$mappings"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi