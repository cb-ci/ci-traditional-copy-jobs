#!/bin/bash
set -e

source ./set-test-env.sh

# Function to deploy a job config to remote Jenkins
# Parameters:
#   $1 - job_path: The job path/name (e.g., "mbtest", "simpletest")
#   $2 - config_file: Path to the local config.xml file
deploy_job_config() {
  local job_path="$1"
  local config_file="$2"
  
  echo "Deploying job: $job_path"
  
  # Create the job directory on remote host
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && mkdir -p \"$JENKINS_HOME/jobs/$job_path\" && chmod -R 755 \"$JENKINS_HOME/jobs/$job_path\""
  
  # Copy the job config file to remote host
  scp $SCP_OPTS "$config_file" "$SSH_USER@$SSH_HOST:$JENKINS_HOME/jobs/$job_path/config.xml"
  
  # Backup the job config file
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && cp \"$JENKINS_HOME/jobs/$job_path/config.xml\" \"$JENKINS_HOME/jobs/$job_path/config.xml.bak\""
}

# Deploy test jobs
deploy_job_config "mbtest" "$TEST_JOB_MB_CONFIG_FILE"
deploy_job_config "simpletest" "$TEST_JOB_SIMPLE_CONFIG_FILE"

# Update tokens
./updateJenkinsConfigTokens.sh

# Verify update
# Function to verify job config updates
# Parameters:
#   $1 - job_path: The job path/name to verify
verify_job_update() {
  local job_path="$1"
  
  echo "########################"
  echo "Verifying job: $job_path"
  
  # Show the diff between current and backup
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && diff \"$JENKINS_HOME/jobs/$job_path/config.xml\" \"$JENKINS_HOME/jobs/$job_path/config.xml.bak\"" || true
  
  # Show file details
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && ls -l \"$JENKINS_HOME/jobs/$job_path/config.xml\""
  
  # Show token values
  ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
    "${SUDO} set -x && cat \"$JENKINS_HOME/jobs/$job_path/config.xml\" | grep -i token"
}

# Verify updates for all test jobs
verify_job_update "mbtest"
verify_job_update "simpletest"