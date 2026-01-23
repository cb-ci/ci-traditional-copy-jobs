#!/bin/bash
set -e
#set -x
# --- Configuration ---
source ./set-test-env.sh

# Start docker containers
init


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
  --job-path "$TEST_JOB_NAME_SIMPLE" \
  --job-path "$TEST_JOB_NAME_MB" \
  --jenkins-user "$JENKINS_USER" \
  --jenkins-token "$JENKINS_TOKEN" \
  --jenkins-url-target "http://localhost:8082" \
  --verbose \
  --force

# 7. Verify the copy result
verifyResult "$TEST_JOB_NAME_SIMPLE"
verifyResult "$TEST_JOB_NAME_MB"

# 8. Update tokens
./updateJenkinsConfigTokens.sh
# Verify updates for all test jobs
verify_token_update "$TEST_JOB_NAME_MB"
verify_token_update "$TEST_JOB_NAME_SIMPLE"







