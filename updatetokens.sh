
TOKEN=${1:-"mytoken"}
#SUDO="sudo -i"
SUDO=""
# Note: ssh uses -p for port, scp uses -P for port
SSH_OPTS="-p 2222 -i ./jenkins_test_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP_OPTS="-P 2222 -i ./jenkins_test_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_USER="root"
SSH_HOST="localhost"
JENKINS_HOME="/var/jenkins_home"

# Create job directory on remote host
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && mkdir -p \"$JENKINS_HOME/jobs/mbtest\" && chmod 755 \"$JENKINS_HOME/jobs/mbtest\""

# Copy config file to remote host
scp $SCP_OPTS ./sample-mb-mulitscan-trigger-config.xml "$SSH_USER@$SSH_HOST:$JENKINS_HOME/jobs/mbtest/config.xml"

# Backup config file
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && cp \"$JENKINS_HOME/jobs/mbtest/config.xml\" \"$JENKINS_HOME/jobs/mbtest/config.xml.bak\""

# Update token in config file
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && find \"$JENKINS_HOME/jobs/mbtest\" \"$JENKINS_HOME/jobs\" -iname 'config.xml' -exec sed -i 's|<token>[^<]*</token>|<token>$TOKEN</token>|g' {} \;"

# Verify update
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/mbtest/config.xml\" \"$JENKINS_HOME/jobs/mbtest/config.xml.bak\""