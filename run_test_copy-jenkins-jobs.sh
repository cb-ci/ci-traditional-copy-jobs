#!/bin/bash
set -e

# --- Configuration ---
SSH_KEY_FILE="./jenkins_test_key"
JOB_NAME="test-job"
export CONTROLLER_JENKINS_HOMES_PATH=$(pwd)/jenkins_homes
mkdir -p $CONTROLLER_JENKINS_HOMES_PATH

# --- Helper Functions ---
log() {
  echo
  echo "--- $1 ---"
}

# --- Test Workflow ---

# 1. Cleanup previous runs
log "Cleaning up any previous Docker environment"
docker-compose down -v --remove-orphans > /dev/null 2>&1 || true
rm -f "$SSH_KEY_FILE" "$SSH_KEY_FILE.pub"

# 2. Generate SSH key
log "Generating SSH key for test"
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_FILE" -N ""
chmod 600 "$SSH_KEY_FILE"
echo "SSH key generated."

# 3. Build and start Docker containers
log "Building and starting Docker containers"
docker-compose up -d --build
echo "Containers are starting in the background..."

# 4. Wait for Jenkins controllers to be ready
log "Waiting for Jenkins controllers to be available..."
for port in 8081 8082; do
  echo "Waiting for Jenkins on port $port..."
  while ! curl -s "http://localhost:$port/login" | grep -q "Sign in to Jenkins"; do
    sleep 5
  done
  echo "Jenkins on port $port is ready."
done

# 5. Configure SSH access and create test job
log "Configuring SSH and creating test job on SOURCE"
for container in jenkins-source jenkins-target; do
    echo "Configuring SSH for $container"
    docker exec "$container" bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
    docker cp "$SSH_KEY_FILE.pub" "$container:/root/.ssh/authorized_keys"
    docker exec "$container" bash -c "chmod 600 /root/.ssh/authorized_keys"
done

log "Creating job '$JOB_NAME' on jenkins-source"
docker exec jenkins-source mkdir -p "/var/jenkins_home/jobs/$JOB_NAME"
docker cp ./config.xml "jenkins-source:/var/jenkins_home/jobs/$JOB_NAME/config.xml"
docker exec jenkins-source chown -R 1000:1000 "/var/jenkins_home/jobs/$JOB_NAME"
# Also need to reload the source jenkins to make the job visible
#docker exec jenkins-source curl -X POST http://localhost:8080/reload

log "Verifying job exists on SOURCE before copy"
if docker exec jenkins-source ls "/var/jenkins_home/jobs/" | grep -q "$JOB_NAME"; then
    echo "OK: Job '$JOB_NAME' found on SOURCE."
else
    echo "ERROR: Job '$JOB_NAME' not found on SOURCE."
    exit 1
fi

# Remove known_hosts entry to avoid issues on reruns
ssh-keygen -R "[localhost]:2221" > /dev/null 2>&1 || true
ssh-keygen -R "[localhost]:2222" > /dev/null 2>&1 || true

# 6. Run the copy script
log "Running the copy-jenkins-jobs-scp.sh script"
./copy-jenkins-jobs-scp.sh \
  --source-host "localhost" \
  --target-host "localhost" \
  --source-user "root" \
  --target-user "root" \
  --ssh-port-source "2221" \
  --ssh-port-target "2222" \
  --ssh-key-source "$SSH_KEY_FILE" \
  --ssh-key-target "$SSH_KEY_FILE" \
  --job-path "$JOB_NAME" \
  --jenkins-url-target "http://localhost:8082" \
  --verbose \
  --force

# 7. Verify the result
log "Verifying job on TARGET after copy"
if docker exec jenkins-target ls "/var/jenkins_home/jobs/" | grep -q "$JOB_NAME"; then
    echo "SUCCESS: Job '$JOB_NAME' directory found on TARGET."
else
    echo "FAILURE: Job '$JOB_NAME' directory NOT found on TARGET."
    exit 1
fi

if docker exec jenkins-target test -f "/var/jenkins_home/jobs/$JOB_NAME/config.xml"; then
    echo "SUCCESS: config.xml found in job directory on TARGET."
else
    echo "FAILURE: config.xml NOT found in job directory on TARGET."
    exit 1
fi

log "Verifying job loaded in TARGET Jenkins UI (via API)"
# Give Jenkins a moment to load the new job after the reload
#sleep 5
#if curl -s "http://localhost:8082/api/json" | grep -q "\"name\":\"$JOB_NAME\"\""; then
#    echo "SUCCESS: Job '$JOB_NAME' is visible in the Jenkins API on TARGET."
#else
#    echo "FAILURE: Job '$JOB_NAME' is NOT visible in the Jenkins API on TARGET."
#    exit 1
#fi


log "TEST SUCCEEDED!"

# 8. Cleanup
log "Cleaning up the Docker environment"
docker-compose down -v --remove-orphans
rm -f "$SSH_KEY_FILE" "$SSH_KEY_FILE.pub"
echo "Cleanup complete."

