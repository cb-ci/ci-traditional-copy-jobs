#!/bin/bash
#
# updateJenkinsConfigTokens.sh
#
# Description:
#   Updates webhook tokens in Jenkins job configuration files (config.xml) on a remote Jenkins instance.
#   - Handles plain-text tokens (e.g., for multibranch-scan-webhook-trigger).
#   - Handles encrypted tokens (e.g., for GitLab plugin) by encrypting the new token using Jenkins CLI.
#
# Usage:
#   ./updateJenkinsConfigTokens.sh [NEW_TOKEN]
#

set -e  # Exit on error
#set -x


# --- Configuration Loading ---
# Try to source set-test-env.sh from CWD or script directory if available
if [ -f "./set-test-env.sh" ]; then
    source ./set-test-env.sh
elif [ -f "$(dirname "$0")/set-test-env.sh" ]; then
    source "$(dirname "$0")/set-test-env.sh"
elif [ -f "$(dirname "$0")/tests/set-test-env.sh" ]; then
    source "$(dirname "$0")/tests/set-test-env.sh"
fi


# Ensure mandatory variables are set (either via source or env)
: "${TARGET_JENKINS_URL:? "TARGET_JENKINS_URL must be set"}"
: "${JENKINS_ADMIN_USER:? "JENKINS_ADMIN_USER must be set"}"
: "${JENKINS_ADMIN_TOKEN_TARGET:? "JENKINS_ADMIN_TOKEN_TARGET must be set"}"
: "${MY_NEW_TOKEN:? "MY_NEW_TOKEN must be set"}"
: "${TARGET_SSH_OPTS:? "TARGET_SSH_OPTS must be set"}"
: "${SSH_USER:? "SSH_USER must be set"}"
: "${TEST_HOST:? "TEST_HOST must be set"}"  
: "${JENKINS_HOME_PATH:? "JENKINS_HOME_PATH must be set"}"      
#: "${SUDO:? "SUDO must be set"}"      
# export TARGET_SSH_OPTS="-o -p 22 StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ./id_rsa"

# --- Token Encryption ---

log "Encrypting new token using Jenkins Script Console API..."
MY_NEW_TOKEN_ENCRYPTED=$(curl -v -X POST \
  -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_TOKEN_TARGET}" \
  --data-urlencode "script=println(hudson.util.Secret.fromString('${MY_NEW_TOKEN}').getEncryptedValue())" \
  "${TARGET_JENKINS_URL}/scriptText")

log "Encrypted token: $MY_NEW_TOKEN_ENCRYPTED"

# --- Token Updates on Remote Host ---

# 1. Update Plain Text Tokens (<token>)
log "Updating plain-text tokens (<token>) in config.xml files..."
ssh $TARGET_SSH_OPTS "$SSH_USER@$TEST_HOST" \
  "${SUDO} find \"$JENKINS_HOME_PATH/jobs\" -iname 'config.xml' -exec sed -i.bak 's|<token>[^<]*</token>|<token>$MY_NEW_TOKEN</token>|g' {} \;"

# 2. Update Encrypted Tokens (<secretToken>)
log "Updating encrypted tokens (<secretToken>) in config.xml files..."
ssh $TARGET_SSH_OPTS "$SSH_USER@$TEST_HOST" \
  "${SUDO} find \"$JENKINS_HOME_PATH/jobs\" -iname 'config.xml' -exec sed -i.bak 's|<secretToken>[^<]*</secretToken>|<secretToken>$MY_NEW_TOKEN_ENCRYPTED</secretToken>|g' {} \;"

log "Token update complete."

# Optional Verification (only if verify_token_update function exists)
if declare -f verify_token_update > /dev/null; then
    verify_token_update "$TEST_JOB_MB_NAME"
    verify_token_update "$TEST_JOB_SIMPLE_NAME"
fi