#!/bin/bash
set -e

# --- Configuration ---
SSH_KEY_SOURCE_FILE="./jenkins_test_key_source"
SSH_KEY_TARGET_FILE="./jenkins_test_key_target"
JOB_NAME="test-sync-job"
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
rm -f "$SSH_KEY_SOURCE_FILE" "$SSH_KEY_SOURCE_FILE.pub"
rm -f "$SSH_KEY_TARGET_FILE" "$SSH_KEY_TARGET_FILE.pub"
# Kill any existing ssh-agent we might have started in a previous partial run (hard to track, so rely on standard exit)

# 2. Generate SSH keys
log "Generating SSH keys for test"
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_SOURCE_FILE" -N ""
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_TARGET_FILE" -N ""
chmod 600 "$SSH_KEY_SOURCE_FILE" "$SSH_KEY_TARGET_FILE" 
echo "SSH keys generated."

# 3. Start SSH Agent and add keys
log "Starting SSH Agent"
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_SOURCE_FILE"
ssh-add "$SSH_KEY_TARGET_FILE"

# 4. Build and start Docker containers
log "Building and starting Docker containers"
# Force build to ensure rsync is installed
docker-compose up -d --build
echo "Containers are starting in the background..."

# 5. Wait for Jenkins controllers to be ready
log "Waiting for Jenkins controllers to be available..."
for port in 8081 8082; do
  echo "Waiting for Jenkins on port $port..."
  while ! curl -s "http://localhost:$port/login" | grep -q "Sign in to Jenkins"; do
    sleep 5
  done
  echo "Jenkins on port $port is ready."
done

# 6. Configure SSH access and create test job
log "Configuring SSH and creating test job on SOURCE"

# Configure SOURCE container: Needs Source Key public in authorized_keys (for self/test?) 
# NO, for this test:
# Local Machine -> Source Container (needs Source Public Key in Source's authorized_keys)
# Source Container -> Target Container (needs Target Public Key in Target's authorized_keys? AND Source needs private key? NO)
# WAIT. SSH Agent Forwarding means:
# Local (has Keys) -> SSH(-A) -> Source (Socket Forwarded) -> SSH (uses Forwarded Socket) -> Target.
# So:
# 1. Local can SSH to Source. (Source needs Local's Key-A public in authorized_keys)
# 2. Local can SSH to Target. (Target needs Local's Key-B public in authorized_keys)
# 3. When Source ssh's to Target, it uses Key-B from the forwarded agent. 
# So Target needs Key-B public in authorized_keys.
# AND Source needs Key-A public in authorized_keys so Local can connect to it securely first.

# Let's simplify and use one key pair for both if easiest, but distinct is better test.
# SOURCE Container: Needs SSH_KEY_SOURCE_FILE.pub in authorized_keys.
# TARGET Container: Needs SSH_KEY_TARGET_FILE.pub in authorized_keys.

# setup source
docker exec jenkins-source bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
docker cp "$SSH_KEY_SOURCE_FILE.pub" "jenkins-source:/root/.ssh/authorized_keys"
docker exec jenkins-source bash -c "chmod 600 /root/.ssh/authorized_keys"

# setup target
docker exec jenkins-target bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
docker cp "$SSH_KEY_TARGET_FILE.pub" "jenkins-target:/root/.ssh/authorized_keys"
docker exec jenkins-target bash -c "chmod 600 /root/.ssh/authorized_keys"


log "Creating job '$JOB_NAME' on jenkins-source"
docker exec jenkins-source mkdir -p "/var/jenkins_home/jobs/$JOB_NAME"
docker cp ./config.xml "jenkins-source:/var/jenkins_home/jobs/$JOB_NAME/config.xml"
docker exec jenkins-source chown -R 1000:1000 "/var/jenkins_home/jobs/$JOB_NAME"

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

# 7. Run the sync script
log "Running the sync-jobs-rsync.sh script"
# We DO NOT pass private keys here because they are in the agent!
./sync-jobs-rsync.sh \
  --source-host "localhost" \
  --target-host "jenkins-target" \
  --source-user "root" \
  --target-user "root" \
  --ssh-port-source "2221" \
  --ssh-port-target "22" \
  --job-path "$JOB_NAME" \
  --dry-run \
  --verbose

echo "Dry run complete. Now running actual sync..."

./sync-jobs-rsync.sh \
  --source-host "localhost" \
  --target-host "jenkins-target" \
  --source-user "root" \
  --target-user "root" \
  --ssh-port-source "2221" \
  --ssh-port-target "22" \
  --job-path "$JOB_NAME" \
  --delete \
  --verbose

# 8. Verify the result
log "Verifying job on TARGET after sync"
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

log "TEST SUCCEEDED!"

# 9. Cleanup
log "Cleaning up"
# Stop agent
kill $SSH_AGENT_PID
docker-compose down -v --remove-orphans
rm -f "$SSH_KEY_SOURCE_FILE" "$SSH_KEY_SOURCE_FILE.pub"
rm -f "$SSH_KEY_TARGET_FILE" "$SSH_KEY_TARGET_FILE.pub"
echo "Cleanup complete."
