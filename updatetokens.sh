
TOKEN=${1:-"mytoken"}
#SUDO="sudo -i"
SUDO=""
SSH_OPTS="-p 2222 -i ./jenkins_test_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_USER="root"
SSH_HOST="localhost"
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
"${SUDO} find \"\$JENKINS_HOME/jobs\" -iname 'config.xml' -exec sed -i 's|<token>[^<]*</token>|<token>$TOKEN</token>|g' {} \;"