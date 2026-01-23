#!/bin/bash
set -e
#set -x
# --- Configuration ---
source ./set-test-env.sh
# --- Test Workflow ---
# Cleanup previous runs
cleanup
# Generate SSH keys for source and target
generate_ssh_key_if_needed "$SSH_KEY_SOURCE_FILE"
generate_ssh_key_if_needed "$SSH_KEY_TARGET_FILE"
# Start docker containers
dockerComposeUp

# 7. Run the sync script
log "Running the copy-jenkins-jobs-rsync.sh script"
# We DO NOT pass private keys here because they are in the agent!
./copy-jenkins-jobs-rsync.sh \
  --source-host "localhost" \
  --target-host "jenkins-target" \
  --source-user "root" \
  --target-user "root" \
  --ssh-port-source "2221" \
  --ssh-port-target "22" \
  --job-path "$TEST_JOB_NAME_SIMPLE" \
  --job-path "$TEST_JOB_NAME_MB" \
  --dry-run \
  --verbose

echo "Dry run complete. Now running actual sync..."

./copy-jenkins-jobs-rsync.sh \
  --source-host "localhost" \
  --target-host "jenkins-target" \
  --source-user "root" \
  --target-user "root" \
  --ssh-port-source "2221" \
  --ssh-port-target "22" \
  --job-path "$TEST_JOB_NAME_SIMPLE" \
  --job-path "$TEST_JOB_NAME_MB" \
  --delete \
  --verbose


# 7. Verify the copy result
verifyResult "$TEST_JOB_NAME_SIMPLE"
verifyResult "$TEST_JOB_NAME_MB"

# 8. Update tokens
./updateJenkinsConfigTokens.sh
# Verify updates for all test jobs
verify_token_update "$TEST_JOB_NAME_MB"
verify_token_update "$TEST_JOB_NAME_SIMPLE"

