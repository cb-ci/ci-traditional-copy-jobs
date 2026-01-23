#!/bin/bash
set -e
#set -x
# --- Configuration ---
source ./set-test-env.sh
init

# 7. Run the sync script
log "Running the copy-jenkins-jobs-rsync.sh script"
# We DO NOT pass private keys here because they are in the agent!
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

echo "Dry run complete. Now running actual sync..."

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

reloadJenkins "$JENKINS_HOST_TARGET"

# 7. Verify the copy result
verifyResult "$TEST_JOB_NAME_SIMPLE"
verifyResult "$TEST_JOB_NAME_MB"

# 8. Update tokens
./updateJenkinsConfigTokens.sh
# Verify updates for all test jobs
verify_token_update "$TEST_JOB_NAME_MB"
verify_token_update "$TEST_JOB_NAME_SIMPLE"

