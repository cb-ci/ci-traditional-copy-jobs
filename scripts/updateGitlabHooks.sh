#!/bin/bash

# Script to parse Git URLs from multibranch and pipeline projects in a YAML file
# and synchronize GitLab project hooks.
# Usage: ./scanRepos.sh [path-to-yaml-file]

set -euo pipefail

# --- Constants & Defaults ---
API_URL="${API_URL:-https://gitlab.com/api/v4}"
DEFAULT_YAML_FILE="../tests/testdata/casc-jobs.yaml"

# --- Environment Configuration ---
# Ideally, set these in your environment or a .env file.
# We use defaults here to maintain compatibility with the original script's flow.
GITLAB_TOKEN="${GITLAB_TOKEN:-glpat-YOUR_TOKEN}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-$(openssl rand -base64 32)}"
WEBHOOK_REFERENCE_URL_PREFIX="${WEBHOOK_REFERENCE_URL_PREFIX:-https://ci.sourcecontroller.com}"
WEBHOOK_TARGET_URL_PREFIX="${WEBHOOK_TARGET_URL_PREFIX:-https://ci.targetcontroller.com}"

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

check_requirements() {
    local missing=()
    for cmd in yq jq curl openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required commands: ${missing[*]}"
        error "Please install them first (e.g., brew install yq jq)."
        exit 1
    fi
}

validate_env() {
    if [[ -z "$GITLAB_TOKEN" ]]; then
        error "GITLAB_TOKEN is not set."
        exit 1
    fi

    if [[ -z "$WEBHOOK_TARGET_URL_PREFIX" ]]; then
        error "WEBHOOK_TARGET_URL_PREFIX is not set."
        exit 1
    fi
    
    log "Using API: $API_URL"
    log "Reference Prefix: $WEBHOOK_REFERENCE_URL_PREFIX"
    log "Target Prefix: $WEBHOOK_TARGET_URL_PREFIX"
}

get_project_hooks() {
    local encoded_project="$1"
    curl --silent --fail --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$API_URL/projects/$encoded_project/hooks"
}

create_hook_payload() {
    local list_body="$1"
    local ref_hook_id="$2"
    local target_prefix="$3"
    local secret_token="${4:-}"

    # Extract the URI from the reference hook and append it to the target prefix
    local ref_url
    ref_url=$(echo "$list_body" | jq -r ".[] | select(.id == $ref_hook_id) | .url")
    
    local ref_uri
    ref_uri=$(echo "$ref_url" | sed -E "s|^${WEBHOOK_REFERENCE_URL_PREFIX}||")
    
    local target_url="${target_prefix}${ref_uri}"

    # Build payload by selecting the reference hook and updating the URL
    local payload
    payload=$(echo "$list_body" | jq -c "
        .[] | select(.id == $ref_hook_id) | 
        {
            url: \"$target_url\",
            push_events,
            tag_push_events,
            merge_requests_events,
            repository_update_events,
            enable_ssl_verification,
            alert_status,
            disabled_until,
            push_events_branch_filter,
            branch_filter_strategy,
            custom_webhook_template,
            project_id,
            issues_events,
            confidential_issues_events,
            note_events,
            confidential_note_events,
            pipeline_events,
            wiki_page_events,
            deployment_events,
            feature_flag_events,
            job_events,
            releases_events,
            milestone_events,
            emoji_events,
            resource_access_token_events,
            vulnerability_events
        }")

    # Inject secret token if provided
    if [[ -n "$secret_token" ]]; then
        payload=$(echo "$payload" | jq -c --arg secret "$secret_token" '. + {token: $secret}')
    fi

    echo "$payload"
}

add_hook_to_project() {
    local encoded_project="$1"
    local payload="$2"

    local response
    response=$(curl --silent --write-out "\n %{http_code}" \
        --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$API_URL/projects/$encoded_project/hooks")

    local status=$(echo "$response" | tail -n1)
    if [[ "$status" -eq 201 ]]; then
        return 0
    else
        error "Failed to create hook (Status: $status). Response: $(echo "$response" | sed '$d')"
        return 1
    fi
}

process_repo() {
    local url="$1"
    # Extract project path (e.g., group/repo) from URL
    local repo_path
    repo_path=$(echo "$url" | sed -E 's|.*gitlab\.com[:/](.*)\.git$|\1|')
    local encoded_project=$(echo "$repo_path" | sed 's|/|%2F|g')

    log "--------------------------------------------------"
    log "Project: $repo_path"

    local hooks_list
    if ! hooks_list=$(get_project_hooks "$encoded_project"); then
        error "Could not fetch hooks for $repo_path. Check your token or project path."
        return
    fi

    local ref_hook_ids
    ref_hook_ids=$(echo "$hooks_list" | jq -r ".[] | select(.url | startswith(\"$WEBHOOK_REFERENCE_URL_PREFIX\")) | .id")

    if [[ -z "$ref_hook_ids" || "$ref_hook_ids" == "null" ]]; then
        warn "No reference hooks found for $repo_path"
        return
    fi

    for ref_id in $ref_hook_ids; do
        log "Syncing hook (Ref ID: $ref_id)..."
        local payload
        payload=$(create_hook_payload "$hooks_list" "$ref_id" "$WEBHOOK_TARGET_URL_PREFIX" "$WEBHOOK_SECRET")
        
        if add_hook_to_project "$encoded_project" "$payload"; then
            success "Hook synchronized for $repo_path"
        fi
    done
}

# --- Main Script Execution ---

check_requirements

YAML_FILE="${1:-$DEFAULT_YAML_FILE}"
if [[ ! -f "$YAML_FILE" ]]; then
    error "YAML file not found: $YAML_FILE"
    exit 1
fi

validate_env

log "Parsing URLs from: $YAML_FILE"

# Extract and deduplicate Git URLs
URLS=()
while IFS= read -r url; do
    [[ -n "$url" ]] && URLS+=("$url")
done < <( (
    # Extract from multibranch projects
    yq eval '.items[] | select(.kind == "multibranch") | .sourcesList[].branchSource.source.gitlab | select(. != null) | "https://gitlab.com/" + .projectPath + ".git"' "$YAML_FILE"
    # Extract from standard pipeline projects
    yq eval '.items[] | select(.kind == "pipeline") | .definition.cpsScmFlowDefinition.scm.scmGit.userRemoteConfigs[].userRemoteConfig.url' "$YAML_FILE"
) | sort | uniq | grep -v 'null' || true )

if [ ${#URLS[@]} -eq 0 ]; then
    warn "No valid Git URLs found in $YAML_FILE"
    exit 0
fi

log "Found ${#URLS[@]} unique project(s)."

for url in "${URLS[@]}"; do
    process_repo "$url"
done

log "========================================"
success "Processing complete."