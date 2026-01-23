#!/bin/bash
set -e
#set -x
# --- Configuration ---
source ./set-test-env.sh

# Initialize the test environment
init

# Run the copy script (SCP version)
log "Running the copy-jenkins-jobs-scp.sh script"
./copy-jenkins-jobs-scp.sh \
  --source-host "$MY_HOST" \
  --target-host "$MY_HOST" \
  --source-user "$SSH_USER" \
  --target-user "$SSH_USER" \
  --ssh-port-source "$SSH_PORT_SOURCE" \
  --ssh-port-target "$SSH_PORT_TARGET" \
  --ssh-key-source "$SSH_KEY_FILE" \
  --ssh-key-target "$SSH_KEY_FILE" \
  --job-path "$TEST_JOB_NAME_SIMPLE" \
  --job-path "$TEST_JOB_NAME_MB" \
  --jenkins-user "$JENKINS_USER" \
  --jenkins-token "$JENKINS_TOKEN" \
  --jenkins-url-target "$JENKINS_URL_TARGET" \
  --verbose \
  --force

# Reload Jenkins configuration on target to pick up changes
#reloadJenkins "$JENKINS_URL_TARGET"

# Verify the copy result
verifyResult "$TEST_JOB_NAME_SIMPLE"
verifyResult "$TEST_JOB_NAME_MB"

# Update webhook tokens
./updateJenkinsConfigTokens.sh










