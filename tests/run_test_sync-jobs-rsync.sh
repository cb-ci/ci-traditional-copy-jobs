#!/bin/bash
set -e

# --- Configuration ---
# Get current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/set-test-env.sh"

# Initialize the test environment (cleanup, keys, containers, source jobs)
init

# --- Execution ---

log "Testing copy-jenkins-jobs-rsync.sh (Dry Run)"
# We DO NOT pass private keys here because they are expected to be in the SSH agent (initialized in init -> generate_ssh_key_if_needed)
"$PROJECT_ROOT/copy-jenkins-jobs-rsync.sh" \
  --source-host "$TEST_HOST" \
  --target-host "$TEST_HOST" \
  --source-user "$SSH_USER" \
  --target-user "$SSH_USER" \
  --ssh-key-file "$TEST_SSH_KEY_FILE" \
  --ssh-port-source "$SOURCE_SSH_PORT" \
  --ssh-port-target "$TARGET_SSH_PORT" \
  --job-path "$TEST_JOB_SIMPLE_NAME" \
  --job-path "$TEST_JOB_MB_NAME" \
  --dry-run \
  --verbose

log "Dry run complete. Now running actual sync..."

"$PROJECT_ROOT/copy-jenkins-jobs-rsync.sh" \
  --source-host "$TEST_HOST" \
  --target-host "$TEST_HOST" \
  --source-user "$SSH_USER" \
  --target-user "$SSH_USER" \
  --ssh-key-file "$TEST_SSH_KEY_FILE" \
  --ssh-port-source "$SOURCE_SSH_PORT" \
  --ssh-port-target "$TARGET_SSH_PORT" \
  --job-path "$TEST_JOB_SIMPLE_NAME" \
  --job-path "$TEST_JOB_MB_NAME" \
  --delete \
  --verbose

# Reload Jenkins configuration on target to pick up changes
reload_jenkins "$TARGET_JENKINS_URL"

# Verify the copy result
verify_result "$TEST_JOB_SIMPLE_NAME"
verify_result "$TEST_JOB_MB_NAME"

# Update tokens
log "Updating webhook tokens..."
"$PROJECT_ROOT/updateJenkinsConfigTokens.sh"

log "Rsync Sync Integration Test Finished Successfully!"
