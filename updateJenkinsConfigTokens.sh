#!/bin/bash
set -e  # Exit on error
set -x  # Print commands

source ./set-test-env.sh

# Get encrypted token, used for GitLab Plugin

if [ ! -f jenkins-cli.jar ]; then
    curl -o jenkins-cli.jar $JENKINS_HOST/jnlpJars/jenkins-cli.jar
    chmod +x jenkins-cli.jar
fi
MY_NEW_TOKEN_ENCRYPTED=$(echo "println(hudson.util.Secret.fromString('$MY_NEW_TOKEN').getEncryptedValue())" | \
java -jar jenkins-cli.jar -s $JENKINS_HOST -auth admin:admin_token groovy =)


# Update token in config file

# This replacement is specifc to multibranch-scan-webhook-trigger plugin
# The multibranch-scan-webhook-trigger plugin uses a token in PLAIN_TEXT to authenticate webhooks
# It will update the token in the config.xml file
# Other triggers like gitlab or github webhook trigger might have different tokens patterns or configuration file paths
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && find  \"$JENKINS_HOME/jobs\" -iname 'config.xml' -exec sed -i 's|<token>[^<]*</token>|<token>$MY_NEW_TOKEN</token>|g' {} \;"

# This replacement is specifc to gitlab plugin
# The gitlab plugin uses a ENCRYPTED token to authenticate webhooks
# It will update the token in the config.xml file
# Other triggers like gitlab or github webhook trigger might have different tokens patterns or configuration file paths

ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && find  \"$JENKINS_HOME/jobs\" -iname 'config.xml' -exec sed -i 's|<secretToken>[^<]*</secretToken>|<secretToken>$MY_NEW_TOKEN_ENCRYPTED</secretToken>|g' {} \;"
