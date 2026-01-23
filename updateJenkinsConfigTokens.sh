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
# Environment Variables (set via set-test-env.sh):
#   - JENKINS_HOST: URL of the Jenkins instance
#   - JENKINS_OWNER: Jenkins user for CLI authentication
#   - JENKINS_TOKEN: Jenkins API token for CLI authentication
#   - SSH_OPTS, SSH_USER, SSH_HOST: SSH connection details
#

set -e  # Exit on error


source ./set-test-env.sh



# --- Token Encryption ---

if [ ! -f jenkins-cli.jar ]; then
    log "Downloading jenkins-cli.jar..."
    curl -o jenkins-cli.jar -s $JENKINS_URL_TARGET/jnlpJars/jenkins-cli.jar
    chmod +x jenkins-cli.jar
fi

log "Encrypting new token using Jenkins CLI..."
MY_NEW_TOKEN_ENCRYPTED=$(echo "println(hudson.util.Secret.fromString('$MY_NEW_TOKEN').getEncryptedValue())" | \
java -jar jenkins-cli.jar -s $JENKINS_URL_TARGET -auth ${JENKINS_OWNER}:${JENKINS_TOKEN} groovy =)
log "Encrypted token: $MY_NEW_TOKEN_ENCRYPTED"

# Verify encryption (optional, for debugging)
MY_DECRYPTED_TOKEN=$(echo "println(hudson.util.Secret.fromString('$MY_NEW_TOKEN_ENCRYPTED').getPlainText())" | \
java -jar jenkins-cli.jar -s $JENKINS_URL_TARGET -auth ${JENKINS_OWNER}:${JENKINS_TOKEN} groovy =)
log "Decrypted verify: $MY_DECRYPTED_TOKEN (should match '$MY_NEW_TOKEN')"

# Token Updates on Remote Host ---

# Update Plain Text Tokens
# Specific to: multibranch-scan-webhook-trigger plugin and others using <token>
log "Updating plain-text tokens (<token>) in config.xml files..."
ssh $SSH_OPTS_TARGET "$SSH_USER@$MY_HOST" \
  "${SUDO} set -x && find  \"$JENKINS_HOME/jobs\" -iname 'config.xml' -exec sed -i.bak 's|<token>[^<]*</token>|<token>$MY_NEW_TOKEN</token>|g' {} \;"

# Update Encrypted Tokens
# Specific to: gitlab-plugin and others using <secretToken>
log "Updating encrypted tokens (<secretToken>) in config.xml files..."
ssh $SSH_OPTS_TARGET "$SSH_USER@$MY_HOST" \
  "${SUDO} set -x && find  \"$JENKINS_HOME/jobs\" -iname 'config.xml' -exec sed -i.bak 's|<secretToken>[^<]*</secretToken>|<secretToken>$MY_NEW_TOKEN_ENCRYPTED</secretToken>|g' {} \;"

log "Token update complete."


# Verify update on tokens
verify_token_update() {
  local job_path="$1"
  
  log "Verifying job: $job_path"
  
  # Show the diff between current and backup
  ssh $SSH_OPTS_TARGET "$SSH_USER@$MY_HOST" \
    "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/$job_path/config.xml\" \"$JENKINS_HOME/jobs/$job_path/config.xml.bak\"" || true
  
  # Show file details
  ssh $SSH_OPTS_TARGET "$SSH_USER@$MY_HOST" \
    "${SUDO} set -x && ls -l \"$JENKINS_HOME/jobs/$job_path/config.xml\""
  
  # Show token values
  ssh $SSH_OPTS_TARGET "$SSH_USER@$MY_HOST" \
    "${SUDO} set -x && cat \"$JENKINS_HOME/jobs/$job_path/config.xml\" | grep -i token"
}
verify_token_update "$TEST_JOB_NAME_MB"
verify_token_update "$TEST_JOB_NAME_SIMPLE"