#!/bin/bash
set -e
#set -x
# --- Configuration ---
source ./set-test-env.sh

# Initialize the test environment
init

# Run the sync script
log "Running the copy-jenkins-jobs-rsync.sh script"
./copy-jenkins-jobs-rsync.sh \
  --source-host "$MY_HOST" \
  --target-host "$MY_HOST" \
  --source-user "$SSH_USER" \
  --target-user "$SSH_USER" \
  --ssh-port-source "$SSH_PORT_SOURCE" \
  --ssh-port-target "$SSH_PORT_TARGET" \
  --job-path "$TEST_JOB_NAME_SIMPLE" \
  --job-path "$TEST_JOB_NAME_MB" \
  --dry-run \
  --verbose

log "Dry run complete. Now running actual sync..."

./copy-jenkins-jobs-rsync.sh \
  --source-host "$MY_HOST" \
  --target-host "$MY_HOST" \
  --source-user "$SSH_USER" \
  --target-user "$SSH_USER" \
  --ssh-port-source "$SSH_PORT_SOURCE" \
  --ssh-port-target "$SSH_PORT_TARGET" \
  --job-path "$TEST_JOB_NAME_SIMPLE" \
  --job-path "$TEST_JOB_NAME_MB" \
  --delete \
  --verbose

# Reload Jenkins configuration on target to pick up changes
reloadJenkins "$JENKINS_HOST_TARGET"

# Verify the copy result
verifyResult "$TEST_JOB_NAME_SIMPLE"
verifyResult "$TEST_JOB_NAME_MB"

# Update tokens
./updateJenkinsConfigTokens.sh


