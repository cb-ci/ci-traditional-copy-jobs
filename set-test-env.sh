#!/bin/bash
set -e


# --- Configuration ---

# New token to use
export MY_NEW_TOKEN=${1:-"mytoken"}

# Sudo or not
#SUDO="sudo -i"
export SUDO=""

# SSH Configuration
export SSH_USER="root"
export SSH_HOST="localhost"
export SSH_PORT="2222"
# Note: ssh uses -p for port, scp uses -P for port
export OPTS_COMMON="-i ./jenkins_test_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export SSH_OPTS="-p $SSH_PORT $OPTS_COMMON"
export SCP_OPTS="-P $SSH_PORT $OPTS_COMMON"

# Jenkins Configuration
export JENKINS_HOME="/var/jenkins_home"
export JENKINS_HOST="http://$SSH_HOST:8082"
export TEST_JOB_MB_CONFIG_FILE="./testdata/sample-mb-mulitscan-trigger-config.xml"
export TEST_JOB_SIMPLE_CONFIG_FILE="./testdata/sample-simple-gitlab-config.xml"
