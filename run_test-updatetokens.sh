
MY_NEW_TOKEN=${1:-"mytoken"}
#SUDO="sudo -i"
SUDO=""
# Note: ssh uses -p for port, scp uses -P for port
SSH_OPTS="-p 2222 -i ./jenkins_test_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP_OPTS="-P 2222 -i ./jenkins_test_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_USER="root"
SSH_HOST="localhost"
JENKINS_HOME="/var/jenkins_home"
JENKINS_HOST="http://$SSH_HOST:8082"
TEST_JOB_MB_CONFIG_FILE="./testdata/sample-mb-mulitscan-trigger-config.xml"
TEST_JOB_SIMPLE_CONFIG_FILE="./testdata/sample-simple-gitlab-config.xml"

# Get encrypted token, used for GitLab Plugin
curl -o jenkins-cli.jar $JENKINS_HOST/jnlpJars/jenkins-cli.jar
chmod +x jenkins-cli.jar
MY_NEW_TOKEN_ENCRYPTED=$(echo "println(hudson.util.Secret.fromString('$MY_NEW_TOKEN').getEncryptedValue())" | \
java -jar jenkins-cli.jar -s $JENKINS_HOST -auth admin:admin_token groovy =)

# Create the Multibranch job directory on remote host
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && mkdir -p \"$JENKINS_HOME/jobs/mbtest\" && chmod 755 \"$JENKINS_HOME/jobs/mbtest\""

# Copy the Multibranch job config file to remote host
scp $SCP_OPTS $TEST_JOB_MB_CONFIG_FILE  "$SSH_USER@$SSH_HOST:$JENKINS_HOME/jobs/mbtest/config.xml"

# Backup the Multibranch job config file
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && cp \"$JENKINS_HOME/jobs/mbtest/config.xml\" \"$JENKINS_HOME/jobs/mbtest/config.xml.bak\""

# Create the Simple job directory on remote host
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && mkdir -p \"$JENKINS_HOME/jobs/simpletest\" && chmod 755 \"$JENKINS_HOME/jobs/simpletest\""

# Copy the Simple job config file to remote host
scp $SCP_OPTS $TEST_JOB_SIMPLE_CONFIG_FILE  "$SSH_USER@$SSH_HOST:$JENKINS_HOME/jobs/simpletest/config.xml"

# Backup the Simple job config file
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && cp \"$JENKINS_HOME/jobs/simpletest/config.xml\" \"$JENKINS_HOME/jobs/simpletest/config.xml.bak\""




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



# Verify update
# Multibranch job   
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/mbtest/config.xml\" \"$JENKINS_HOME/jobs/mbtest/config.xml.bak\""

# Simple job
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/simpletest/config.xml\" \"$JENKINS_HOME/jobs/simpletest/config.xml.bak\""