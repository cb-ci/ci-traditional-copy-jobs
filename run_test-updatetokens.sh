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



# Update tokens
./updateJenkinsConfigTokens.sh




# Verify updates for all test jobs
verify_token_update "$TEST_JOB_NAME_MB"
verify_token_update "$TEST_JOB_NAME_SIMPLE"

