#!/bin/bash
set -e


# --- Configuration ---

# New token to use
export MY_NEW_TOKEN=${1:-"mytoken"}

# Sudo or not
#SUDO="sudo -i"
export SUDO=""
export MY_HOST="localhost"
# SSH Configuration
export SSH_USER="root"
# Define test-specific overrides/variables that match docker-compose setup

export SSH_PORT_SOURCE="2221"
export SSH_PORT_TARGET="2222"
export SSH_KEY_FILE="./jenkins_test_key"
export SSH_KEY_SOURCE_FILE=${SSH_KEY_FILE}  #"./jenkins_test_key_source"
export SSH_KEY_TARGET_FILE=${SSH_KEY_FILE}  #"./jenkins_test_key_target"
# Note: ssh uses -p for port, scp uses -P for port
export OPTS_COMMON=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export SSH_OPTS_SOURCE="-p $SSH_PORT_SOURCE -i $SSH_KEY_SOURCE_FILE $OPTS_COMMON"
export SSH_OPTS_TARGET="-p $SSH_PORT_TARGET -i $SSH_KEY_TARGET_FILE $OPTS_COMMON"
export SCP_OPTS_SOURCE="-P $SSH_PORT_SOURCE -i $SSH_KEY_SOURCE_FILE $OPTS_COMMON"
export SCP_OPTS_TARGET="-P $SSH_PORT_TARGET -i $SSH_KEY_TARGET_FILE $OPTS_COMMON"



# Jenkins Configuration
export JENKINS_HOME="/var/jenkins_home"
export JENKINS_SOURCE_CONTAINER_PORT="8081"
export JENKINS_TARGET_CONTAINER_PORT="8082"
export JENKINS_SOURCE_CONTAINER_NAME="jenkins-source"
export JENKINS_TARGET_CONTAINER_NAME="jenkins-target"
export JENKINS_URL_SOURCE="http://$MY_HOST:$JENKINS_SOURCE_CONTAINER_PORT"
export JENKINS_URL_TARGET="http://$MY_HOST:$JENKINS_TARGET_CONTAINER_PORT"
export JENKINS_OWNER="jenkins"
export JENKINS_USER="admin"
export JENKINS_TOKEN="admin_token"
export TEST_JOB_MB_CONFIG_FILE="./testdata/sample-mb-mulitscan-trigger-config.xml"
export TEST_JOB_SIMPLE_CONFIG_FILE="./testdata/sample-simple-gitlab-config.xml"
export TEST_JOB_NAME_SIMPLE="test-job-simple"
export TEST_JOB_NAME_MB="test-job-mb"
export CONTROLLER_JENKINS_HOMES_PATH=$(pwd)/jenkins_homes
mkdir -p $CONTROLLER_JENKINS_HOMES_PATH

# --- Helper Functions ---
log() {
  echo
  echo "--- $1 ---"
}

# Function to generate SSH key if it doesn't exist
# Parameters:
#   $1 - key_file: Path to the SSH key file
generate_ssh_key_if_needed() {
  local key_file="$1"  
  if [ ! -f "$key_file" ] || [ ! -f "$key_file.pub" ]; then
    log "Generating SSH key $key_file"
    ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""
    chmod 600 "$key_file"
    log "SSH key generated $key_file"
  else
    log "SSH key already exists $key_file"
  fi
  log "Starting SSH Agent"
  eval "$(ssh-agent -s)"
  ssh-add "$key_file"
}



cleanup() {    
    log "Cleaning up any previous Docker environment"
    docker-compose down -v --remove-orphans > /dev/null 2>&1 || true
    rm -f "$SSH_KEY_SOURCE_FILE" "$SSH_KEY_SOURCE_FILE.pub" || true
    rm -f "$SSH_KEY_TARGET_FILE" "$SSH_KEY_TARGET_FILE.pub" || true
    rm -Rfv $CONTROLLER_JENKINS_HOMES_PATH/$SOURCE_JENKINS_HOME/jobs/* || true
    rm -Rfv $CONTROLLER_JENKINS_HOMES_PATH/$TARGET_JENKINS_HOME/jobs/* || true
    # Kill any existing ssh-agent we might have started in a previous partial run (hard to track, so rely on standard exit)
    ssh-agent -k > /dev/null 2>&1 || true
    # Remove known_hosts entry to avoid issues on reruns
    ssh-keygen -R "[$MY_HOST]:$SSH_PORT_SOURCE" > /dev/null 2>&1 || true
    ssh-keygen -R "[$MY_HOST]:$SSH_PORT_TARGET" > /dev/null 2>&1 || true
}

# trap cleanup EXIT


# Build and start Docker containers
init() {
    cleanup
    generate_ssh_key_if_needed "$SSH_KEY_SOURCE_FILE"
    generate_ssh_key_if_needed "$SSH_KEY_TARGET_FILE"

    log "Building and starting Docker containers"
    # Force build to ensure rsync is installed
    docker-compose up -d --build
    log "Containers are starting in the background..."

    # Wait for Jenkins controllers to be ready
    log "Waiting for Jenkins controllers to be available..."
    for port in $JENKINS_SOURCE_CONTAINER_PORT $JENKINS_TARGET_CONTAINER_PORT; do
        log "Waiting for Jenkins on port $port..."
        while ! curl -s "http://$MY_HOST:$port/login" | grep -q "Sign in to Jenkins"; do
            sleep 5
        done
        log "Jenkins on port $port is ready."
    done

    # Configure SSH access and create test job
    log "Configuring SSH and creating test job on SOURCE"
    for container in $JENKINS_SOURCE_CONTAINER_NAME $JENKINS_TARGET_CONTAINER_NAME; do
        log "Configuring SSH for $container"
        docker exec "$container" bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
        docker cp "$SSH_KEY_FILE.pub" "$container:/root/.ssh/authorized_keys"
        docker exec "$container" bash -c "chmod 600 /root/.ssh/authorized_keys"
    done



    # Create test jobs
    prepareTestJob "$TEST_JOB_NAME_SIMPLE" "$TEST_JOB_SIMPLE_CONFIG_FILE"
    prepareTestJob "$TEST_JOB_NAME_MB" "$TEST_JOB_MB_CONFIG_FILE"
}   


prepareTestJob() {
    local jobName=$1
    local jobConfigFile=$2
    local container="$JENKINS_SOURCE_CONTAINER_NAME"
    #set -x
    log "Creating job '$jobName' on $container"
    docker exec $container mkdir -p "$JENKINS_HOME/jobs/$jobName"
    docker cp "$jobConfigFile" "$container:$JENKINS_HOME/jobs/$jobName/config.xml"
    docker exec $container chown -R 1000:1000 "$JENKINS_HOME/jobs/$jobName"
    # Also need to reload the source jenkins to make the job visible
    #docker exec jenkins-source curl -X POST http://localhost:8080/reload

    log "Verifying job exists on SOURCE before copy"
    if docker exec $container ls "$JENKINS_HOME/jobs/" | grep -q "$jobName"; then
        log "OK: Job '$jobName' found on SOURCE."
    else
        log "ERROR: Job '$jobName' not found on SOURCE."
        exit 1
    fi
}



# Verify the result
verifyResult() {
    local jobName=$1
    log "Verifying job on TARGET after sync"
    if docker exec $JENKINS_TARGET_CONTAINER_NAME ls "$JENKINS_HOME/jobs/" | grep -q "$jobName"; then
        log "SUCCESS: Job '$jobName' directory found on TARGET."
    else
        log "FAILURE: Job '$jobName' directory NOT found on TARGET."
        exit 1
    fi
    if docker exec $JENKINS_TARGET_CONTAINER_NAME test -f "$JENKINS_HOME/jobs/$jobName/config.xml"; then
        log "SUCCESS: config.xml found in job directory on TARGET."
    else
        log "FAILURE: config.xml NOT found in job directory on TARGET."
        exit 1
    fi
    log "Verifying job loaded in TARGET Jenkins UI (via API)"
    #Give Jenkins a moment to load the new job after the reload
    sleep 5
    if curl -s "$JENKINS_URL_TARGET/api/json" | grep -q "\"name\":\"$jobName\"\""; then
        log "SUCCESS: Job '$jobName' is visible in the Jenkins API on TARGET."
    else
        log "FAILURE: Job '$jobName' is NOT visible in the Jenkins API on TARGET."
        #exit 1
    fi
    log "TEST SUCCEEDED!"
}

reloadJenkins() {
  # Reload Jenkins Configurations
  # Arguments:
  #   $1 - jenkins_url (optional, defaults to JENKINS_HOST)
  local jenkins_url="${1:-$JENKINS_URL_TARGET}"

  log "Attempting to reload Jenkins configuration from disk on target..."  
  CURL_OPTS=("-s" "-X" "POST")
  
  if [ -n "$JENKINS_USER" ] && [ -n "$JENKINS_TOKEN" ]; then
      # Fetch CSRF crumb if protection is enabled
      CRUMB_URL="${jenkins_url}/crumbIssuer/api/json"
      
      # Use sed to parse JSON to avoid dependency on jq
      CRUMB_DATA=$(curl "${CURL_OPTS[@]}" --user "$JENKINS_USER:$JENKINS_TOKEN" "$CRUMB_URL")
      if [[ "$CRUMB_DATA" == *"\"crumbRequestField\":"* ]]; then
          CRUMB_HEADER=$(echo "$CRUMB_DATA" | sed -n 's/.*\"crumbRequestField\":\"\([^\"]*\)\".*/\1/p')
          CRUMB_VALUE=$(echo "$CRUMB_DATA" | sed -n 's/.*\"crumb\":\"\([^\"]*\)\".*/\1/p')
          
          if [ -n "$CRUMB_HEADER" ] && [ -n "$CRUMB_VALUE" ]; then
              CURL_OPTS+=("-H" "$CRUMB_HEADER:$CRUMB_VALUE")
          else
              log "Warning: Could not parse CSRF crumb from response. Reload might fail."
          fi
      fi
      CURL_OPTS+=("--user" "$JENKINS_USER:$JENKINS_TOKEN")
  fi
  
  RELOAD_URL="${jenkins_url}/reload"
  
  HTTP_STATUS=$(curl "${CURL_OPTS[@]}" --write-out "%{http_code}" --output /dev/null "$RELOAD_URL")
  
  if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
    log "Successfully triggered configuration reload on target Jenkins (HTTP $HTTP_STATUS)."
  else
    log "Warning: Failed to trigger configuration reload. Jenkins returned HTTP status $HTTP_STATUS."
    log "You may need to manually reload configuration via the Jenkins UI ('Manage Jenkins' -> 'Reload Configuration from Disk')."
    log "1. Go to your Jenkins UI -> Manage Jenkins."
    log "2. Click 'Reload Configuration from Disk'."
  fi
}
    
