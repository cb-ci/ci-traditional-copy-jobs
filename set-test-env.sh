#!/bin/bash
set -e


# --- Configuration ---

# New token to use
export MY_NEW_TOKEN=${1:-"mytoken"}

# Sudo or not
#SUDO="sudo -i"
export SUDO=""

# SSH Configuration
export SSH_USER="root"
export SSH_HOST="localhost"
export SSH_PORT="2222"
export SSH_KEY_FILE="./jenkins_test_key"
export SSH_KEY_SOURCE_FILE=${SSH_KEY_FILE}  #"./jenkins_test_key_source"
export SSH_KEY_TARGET_FILE=${SSH_KEY_FILE}  #"./jenkins_test_key_target"
# Note: ssh uses -p for port, scp uses -P for port
export OPTS_COMMON="-i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export SSH_OPTS="-p $SSH_PORT $OPTS_COMMON"
export SCP_OPTS="-P $SSH_PORT $OPTS_COMMON"

# Jenkins Configuration
export JENKINS_HOME="/var/jenkins_home"
export JENKINS_HOST="http://$SSH_HOST:8082"
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
    echo "SSH key generated $key_file"
  else
    echo "SSH key already exists $key_file"
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
    ssh-keygen -R "[localhost]:2221" > /dev/null 2>&1 || true
    ssh-keygen -R "[localhost]:2222" > /dev/null 2>&1 || true
}

#trap cleanup EXIT


# Build and start Docker containers
init() {
    cleanup
    generate_ssh_key_if_needed "$SSH_KEY_SOURCE_FILE"
    generate_ssh_key_if_needed "$SSH_KEY_TARGET_FILE"


    log "Building and starting Docker containers"
    # Force build to ensure rsync is installed
    docker-compose up -d --build
    echo "Containers are starting in the background..."

    # Wait for Jenkins controllers to be ready
    log "Waiting for Jenkins controllers to be available..."
    for port in 8081 8082; do
        echo "Waiting for Jenkins on port $port..."
        while ! curl -s "http://localhost:$port/login" | grep -q "Sign in to Jenkins"; do
            sleep 5
        done
        echo "Jenkins on port $port is ready."
    done

    # Configure SSH access and create test job
    log "Configuring SSH and creating test job on SOURCE"
    for container in jenkins-source jenkins-target; do
        echo "Configuring SSH for $container"
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
    local container="jenkins-source"
    #set -x
    log "Creating job '$jobName' on $container"
    docker exec $container mkdir -p "$JENKINS_HOME/jobs/$jobName"
    docker cp "$jobConfigFile" "$container:$JENKINS_HOME/jobs/$jobName/config.xml"
    docker exec $container chown -R 1000:1000 "$JENKINS_HOME/jobs/$jobName"
    # Also need to reload the source jenkins to make the job visible
    #docker exec jenkins-source curl -X POST http://localhost:8080/reload

    log "Verifying job exists on SOURCE before copy"
    if docker exec jenkins-source ls "$JENKINS_HOME/jobs/" | grep -q "$jobName"; then
        echo "OK: Job '$jobName' found on SOURCE."
    else
        echo "ERROR: Job '$jobName' not found on SOURCE."
        exit 1
    fi
}

# Verify update on tokens
verify_token_update() {
  local job_path="$1"
  
  echo "########################"
  echo "Verifying job: $job_path"
  
  # Show the diff between current and backup
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/$job_path/config.xml\" \"$JENKINS_HOME/jobs/$job_path/config.xml.bak\"" || true
  
  # Show file details
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && ls -l \"$JENKINS_HOME/jobs/$job_path/config.xml\""
  
  # Show token values
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && cat \"$JENKINS_HOME/jobs/$job_path/config.xml\" | grep -i token"
}

# Verify the result
verifyResult() {
    local jobName=$1
    log "Verifying job on TARGET after sync"
    if docker exec jenkins-target ls "$JENKINS_HOME/jobs/" | grep -q "$jobName"; then
        echo "SUCCESS: Job '$jobName' directory found on TARGET."
    else
        echo "FAILURE: Job '$jobName' directory NOT found on TARGET."
        exit 1
    fi
    if docker exec jenkins-target test -f "$JENKINS_HOME/jobs/$jobName/config.xml"; then
        echo "SUCCESS: config.xml found in job directory on TARGET."
    else
        echo "FAILURE: config.xml NOT found in job directory on TARGET."
        exit 1
    fi
    log "Verifying job loaded in TARGET Jenkins UI (via API)"
    #Give Jenkins a moment to load the new job after the reload
    sleep 5
    if curl -s "http://localhost:8082/api/json" | grep -q "\"name\":\"$jobName\"\""; then
        echo "SUCCESS: Job '$jobName' is visible in the Jenkins API on TARGET."
    else
        echo "FAILURE: Job '$jobName' is NOT visible in the Jenkins API on TARGET."
        #exit 1
    fi
    log "TEST SUCCEEDED!"
}


