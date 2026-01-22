#!/bin/bash
set -e

source ./set-test-env.sh

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

# Update tokens
./updateJenkinsConfigTokens.sh

# Verify update
# Multibranch job   
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/mbtest/config.xml\" \"$JENKINS_HOME/jobs/mbtest/config.xml.bak\""
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && cat \"$JENKINS_HOME/jobs/mbtest/config.xml\ |grep token""



# Simple job
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/simpletest/config.xml\" \"$JENKINS_HOME/jobs/simpletest/config.xml.bak\""