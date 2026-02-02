#!/bin/bash
set -e

# --- Configuration ---
# Get current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/set-test-env.sh"

# Initialize the test environment (cleanup, keys, containers, source jobs)
init

# --- Execution ---

log "Running the copy-jenkins-jobs-scp.sh script"
"$PROJECT_ROOT/copy-jenkins-jobs-scp.sh" \
  --source-host "$TEST_HOST" \
  --target-host "$TEST_HOST" \
  --source-user "$SSH_USER" \
  --target-user "$SSH_USER" \
  --ssh-port-source "$SOURCE_SSH_PORT" \
  --ssh-port-target "$TARGET_SSH_PORT" \
  --ssh-key-source "$TEST_SSH_KEY_FILE" \
  --ssh-key-target "$TEST_SSH_KEY_FILE" \
  --job-path "$TEST_JOB_SIMPLE_NAME" \
  --job-path "$TEST_JOB_MB_NAME" \
  --jenkins-user "$JENKINS_ADMIN_USER" \
  --jenkins-token "$JENKINS_ADMIN_TOKEN_TARGET" \
  --jenkins-url-target "$TARGET_JENKINS_URL" \
  --verbose \
  --force

# Reload Jenkins configuration on target to pick up changes
reload_jenkins  "$TARGET_JENKINS_URL" "$JENKINS_ADMIN_USER" "$JENKINS_ADMIN_TOKEN_TARGET"

# Verify the copy result
verify_result "$TEST_JOB_SIMPLE_NAME"
verify_result "$TEST_JOB_MB_NAME"

# Update webhook tokens
log "Updating webhook tokens..."
"$PROJECT_ROOT/updateJenkinsConfigTokens.sh"

# Note: updateJenkinsConfigTokens.sh currently has its own verification at the end.
# If we want to verify here specifically:
# verify_token_update "$TEST_JOB_SIMPLE_NAME"
# verify_token_update "$TEST_JOB_MB_NAME"

log "SCP Copy Integration Test Finished Successfully!"
