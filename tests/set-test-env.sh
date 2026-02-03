#!/bin/bash
set -e

# --- Configuration: Environment ---
export TEST_HOST="localhost"
export SSH_USER="root"
export SUDO="" # Set to "sudo -i " if needed

# --- Configuration: Paths ---
# Use absolute path for scripts and test data relative to this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export TEST_DATA_DIR="$SCRIPT_DIR/testdata"
export TEST_WORKDIR="$SCRIPT_DIR"

# Test data files
export CONFIG_FILE_MB="$TEST_DATA_DIR/sample-mb-mulitscan-trigger-config.xml"
export CONFIG_FILE_SIMPLE="$TEST_DATA_DIR/sample-simple-gitlab-config.xml"

# Resource files
export TEST_SSH_KEY_FILE_NAME="id_ed25519"
export TEST_SSH_KEY_FILE="$TEST_WORKDIR/$TEST_SSH_KEY_FILE_NAME"
export TEST_SSH_KEY_PUB="$TEST_SSH_KEY_FILE.pub"
export JENKINS_CLI_JAR="$TEST_WORKDIR/jenkins-cli.jar"

# --- Configuration: Network Ports ---
export SOURCE_SSH_PORT="2221"
export TARGET_SSH_PORT="2222"
export SOURCE_JENKINS_PORT="8081"
export TARGET_JENKINS_PORT="8082"

# --- Configuration: Jenkins ---
export JENKINS_HOME_PATH="/var/jenkins_home"
export SOURCE_CONTAINER_NAME="jenkins-source"
export TARGET_CONTAINER_NAME="jenkins-target"

export SOURCE_JENKINS_URL="http://$TEST_HOST:$SOURCE_JENKINS_PORT"
export TARGET_JENKINS_URL="http://$TEST_HOST:$TARGET_JENKINS_PORT"

export JENKINS_ADMIN_USER="admin"
export JENKINS_ADMIN_PASSWORD="admin"
#export JENKINS_OWNER="cloudbees-core-cm" # User that owns files inside the container
export JENKINS_OWNER="root" # User that owns files inside the container
# Get the admin tokens from the source and target Jenkins controllers
export JENKINS_ADMIN_TOKEN_SOURCE='source_token'
export JENKINS_ADMIN_TOKEN_TARGET='target_token'


# --- Configuration: Job Names ---
export TEST_JOB_MB_NAME="test-job-mb"
export TEST_JOB_SIMPLE_NAME="test-job-simple"
export MY_NEW_TOKEN=${1:-"mytoken"}

# --- Configuration: Docker Persistent Storage ---
export CONTROLLER_JENKINS_HOMES_PATH="$TEST_WORKDIR/jenkins_homes"
mkdir -p "$CONTROLLER_JENKINS_HOMES_PATH"

# --- Compiled SSH/SCP Options ---
export SSH_OPTS_COMMON="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $TEST_SSH_KEY_FILE"
export SOURCE_SSH_OPTS="-p $SOURCE_SSH_PORT $SSH_OPTS_COMMON"
export TARGET_SSH_OPTS="-p $TARGET_SSH_PORT $SSH_OPTS_COMMON"
export SOURCE_SCP_OPTS="-P $SOURCE_SSH_PORT $SSH_OPTS_COMMON"
export TARGET_SCP_OPTS="-P $TARGET_SSH_PORT $SSH_OPTS_COMMON"

# --- Helper Functions ---

log() {
  echo ""
  echo ">>> $1"
}

# Function to generate SSH key if it doesn't exist
generate_ssh_key_if_needed() {
  local key_file="$TEST_SSH_KEY_FILE"
  if [ ! -f "$key_file" ]; then
    log "Generating test SSH key: $key_file"
    ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""
    chmod 600 "$key_file"
  else
    log "Test SSH key already exists: $key_file"
  fi
  
  # Ensure agent is running and key is added
  if [ -z "$SSH_AUTH_SOCK" ]; then
    log "Starting SSH Agent..."
    eval "$(ssh-agent -s)"
  fi
  ssh-add "$key_file" 2>/dev/null
}

cleanup() {    
    log "Cleaning up Docker environment and temporary files..."
    cd "$TEST_WORKDIR"
    docker-compose down -v --remove-orphans > /dev/null 2>&1 || true
    
    rm -f "$TEST_SSH_KEY_FILE" "$TEST_SSH_KEY_PUB" || true
    
    # Clean up mapped volumes on host
    if [ -d "$CONTROLLER_JENKINS_HOMES_PATH" ]; then
        rm -rf "$CONTROLLER_JENKINS_HOMES_PATH"/* || true
    fi

    # Terminate SSH agent if we started it
    if [ -n "$SSH_AGENT_PID" ]; then
        kill "$SSH_AGENT_PID" > /dev/null 2>&1 || true
    fi

    # Clear known_hosts entries for local test ports
    ssh-keygen -R "[$TEST_HOST]:$SOURCE_SSH_PORT" > /dev/null 2>&1 || true
    ssh-keygen -R "[$TEST_HOST]:$TARGET_SSH_PORT" > /dev/null 2>&1 || true
}

# Build and start Docker containers
init() {
    cleanup
    generate_ssh_key_if_needed

    log "Building and starting Docker containers..."
    cd "$TEST_WORKDIR"
    docker-compose up -d --build
    
    # Wait for Jenkins controllers to initialize
    log "Waiting for Jenkins controllers to initialize..."
    for url in "$SOURCE_JENKINS_URL" "$TARGET_JENKINS_URL"; do
        log "Checking readiness for $url"
        local retries=0
        local max_retries=60 # 2 minutes total
        while true; do
            # Check for a successful response (200 OK) or even a 403 (meaning it's up but secure)
            # Standard Jenkins usually returns 200 for the login page
            local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url/login" || echo "000")
            
            if [[ "$status_code" -eq 200 ]]; then
                log "Jenkins is ready at $url (HTTP $status_code)"
                break
            fi
            
            retries=$((retries + 1))
            if [ $retries -ge $max_retries ]; then
                log "ERROR: Jenkins at $url failed to respond after $max_retries attempts."
                exit 1
            fi
            sleep 2
        done
    done

    # Get the admin tokens from the source and target Jenkins controllers
    set -x
    export JENKINS_ADMIN_TOKEN_SOURCE=$(docker exec "$SOURCE_CONTAINER_NAME" cat "$JENKINS_HOME_PATH/tmp_token.txt")
    export JENKINS_ADMIN_TOKEN_TARGET=$(docker exec "$TARGET_CONTAINER_NAME" cat "$JENKINS_HOME_PATH/tmp_token.txt")
    set +x
    # Configure SSH access inside containers
    log "Deploying SSH public keys to containers..."
    for container in "$SOURCE_CONTAINER_NAME" "$TARGET_CONTAINER_NAME"; do
        docker exec "$container" bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
        docker cp "$TEST_SSH_KEY_PUB" "$container:/root/.ssh/authorized_keys"
        docker exec "$container" bash -c "chmod 600 /root/.ssh/authorized_keys"
        docker cp "$TEST_SSH_KEY_FILE" "$container:/root/.ssh/id_ed25519"
        docker exec "$container" bash -c "chmod 600 /root/.ssh/id_ed25519"
    done

    # Prepare test jobs on source
    prepare_test_job "$TEST_JOB_SIMPLE_NAME" "$CONFIG_FILE_SIMPLE"
    prepare_test_job "$TEST_JOB_MB_NAME" "$CONFIG_FILE_MB"
}   

prepare_test_job() {
    local job_name="$1"
    local config_file="$2"
    local container="$SOURCE_CONTAINER_NAME"
    
    log "Creating test job '$job_name' on $container"
    docker exec "$container" mkdir -p "$JENKINS_HOME_PATH/jobs/$job_name"
    docker cp "$config_file" "$container:$JENKINS_HOME_PATH/jobs/$job_name/config.xml"
    #docker exec "$container" chown -R $JENKINS_OWNER:$JENKINS_OWNER "$JENKINS_HOME_PATH/jobs/ && chmod -R 755 $JENKINS_HOME_PATH/jobs/"

    # Quick verify
    if docker exec "$container" ls "$JENKINS_HOME_PATH/jobs/$job_name/config.xml" > /dev/null 2>&1; then
        log "OK: Job '$job_name' created."
    else
        log "ERROR: Failed to create job '$job_name'."
        exit 1
    fi
}

verify_result() {
    local job_name="$1"
    local container="$TARGET_CONTAINER_NAME"
    local url="$TARGET_JENKINS_URL"
    
    log "Verifying job '$job_name' on $container..."
    
    if docker exec "$container" test -f "$JENKINS_HOME_PATH/jobs/$job_name/config.xml"; then
        log "SUCCESS: config.xml found on TARGET."
    else
        log "FAILURE: config.xml NOT found on TARGET."
        exit 1
    fi

    log "Checking Jenkins API for job visibility..."
    # Give it a moment to possibly load if not reloaded yet
    local wait=0
    while [ $wait -lt 15 ]; do
      if curl -s "$url/api/json" | grep -q "\"name\":\"$job_name\""; then
          log "SUCCESS: Job '$job_name' is visible in API."
          return 0
      fi
      sleep 3
      wait=$((wait + 3))
    done
    
    log "WARNING: Job '$job_name' not visible in API yet. Manual reload might be needed."
}

verify_token_update() {
  local job_name="$1"
  local container="$TARGET_CONTAINER_NAME"
  
  log "Verifying tokens for job: $job_name"
  
  # Check if backup exists
  if docker exec "$container" test -f "$JENKINS_HOME_PATH/jobs/$job_name/config.xml.bak"; then
      log "Backup file found."
  fi
  
  # Show token values from config
  log "Current token values in config.xml:"
  docker exec "$container" cat "$JENKINS_HOME_PATH/jobs/$job_name/config.xml" | grep -i token || echo "No tokens found."
}

reload_jenkins() {
  local url="${1:-$TARGET_JENKINS_URL}"
  local user="${2:-$JENKINS_ADMIN_USER}"
  local token="${3:-$JENKINS_ADMIN_TOKEN}"

  log "Triggering Jenkins configuration reload at $url"
  
  local curl_opts=("-s" "-X" "POST" "--user" "$user:$token")
  
  # Get CSRF crumb
  local crumb_resp=$(curl -s --user "$user:$token" "$url/crumbIssuer/api/json")
  if [[ "$crumb_resp" == *"crumbRequestField"* ]]; then
      local header=$(echo "$crumb_resp" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')
      local value=$(echo "$crumb_resp" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
      curl_opts+=("-H" "$header:$value")
  fi
  
  local status=$(curl  "${curl_opts[@]}" --write-out "%{http_code}" --output /dev/null "$url/reload")
  
  if [[ "$status" -ge 200 && "$status" -lt 304 ]]; then
    log "Reload triggered successfully (HTTP $status)."
  else
    log "ERROR: Reload failed (HTTP $status). You might need to reload manually via UI."
  fi
}
