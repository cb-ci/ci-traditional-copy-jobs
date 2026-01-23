#!/bin/bash
#
# copy-jenkins-jobs-rsync.sh
#
# Description:
#   Syncs Jenkins jobs from a SOURCE controller to a TARGET controller using rsync.
#
# Approach:
# - This script runs LOCALLY (e.g., on an admin's laptop).
# - It uses SSH Agent Forwarding (-A) to connect to the SOURCE host.
# - It executes `rsync` on the SOURCE host to PUSH changes to the TARGET host.
#
# Prerequisites:
# - SSH Agent must be running locally with keys for BOTH Source and Target loaded.
# - The SOURCE host must be able to connect to the TARGET host on the specific SSH port.
# - The SSH users must have permissions to read/write the Jenkins job directories.
#

set -Eeo pipefail

# --- Default Configuration ---
SOURCE_JENKINS_HOME="/var/jenkins_home"
TARGET_JENKINS_HOME="/var/jenkins_home"
SSH_PORT_SOURCE="2221"
SSH_PORT_TARGET="2222"
JENKINS_OWNER="root"
DRY_RUN=false
DELETE=false
VERBOSE=false
JOB_PATHS=()
EXCLUDES=()

# --- Script self-awareness ---
SCRIPT_NAME=$(basename "$0")

# --- Logging ---
log() {
  echo "=> $1"
}

verbose_log() {
  if [ "$VERBOSE" = true ]; then
    echo "   [VERBOSE] $1"
  fi
}

die() {
  echo "[ERROR] $1" >&2
  exit 1
}

# --- Usage Information ---
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] 

Synchronizes Jenkins jobs from a source to a target controller using rsync.
Uses SSH Agent Forwarding to execute rsync on the Source (Push model).

Required:
  --source-host <host>          Source Jenkins controller hostname or IP.
  --target-host <host>          Target Jenkins controller hostname or IP.
  --source-user <user>          SSH user for the source host.
  --target-user <user>          SSH user for the target host.
  --job-path <path>             Subpath of the job to sync (e.g., "teamA/job1").
                                Can be specified multiple times.

Optional:
  --source-jenkins-home <path>  Path to Jenkins home on the source.
                                (Default: /var/jenkins_home)
  --target-jenkins-home <path>  Path to Jenkins home on the target.
                                (Default: /var/jenkins_home)
  --ssh-port-source <port>      SSH port for the source host (Default: 22).
  --ssh-port-target <port>      SSH port for the target host (Default: 22).
  --exclude <pattern>           Rsync exclude pattern (e.g., 'builds/', 'workspace/').
                                Can be specified multiple times.
  --delete                      Delete extraneous files on the target (rsync --delete).
  --dry-run                     Show what would be done without making changes.
  --verbose                     Enable verbose logging.
  --help                        Display this help message.

Example:
  $SCRIPT_NAME \\
    --source-host source.jenkins.example.com --source-user admin \\
    --target-host target.jenkins.example.com --target-user admin \\
    --job-path "my-folder/my-job" \\
    --exclude "branches/" --exclude "builds/" --dry-run

EOF
  exit 0
}

# --- Argument Parsing ---
if [ $# -eq 0 ]; then
  usage
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --source-host) SOURCE_HOST="$2"; shift 2 ;;
    --target-host) TARGET_HOST="$2"; shift 2 ;;
    --source-user) SOURCE_USER="$2"; shift 2 ;;
    --target-user) TARGET_USER="$2"; shift 2 ;;
    --job-path) JOB_PATHS+=("$2"); shift 2 ;;
    --source-jenkins-home) SOURCE_JENKINS_HOME="$2"; shift 2 ;;
    --target-jenkins-home) TARGET_JENKINS_HOME="$2"; shift 2 ;;
    --ssh-port-source) SSH_PORT_SOURCE="$2"; shift 2 ;;
    --ssh-port-target) SSH_PORT_TARGET="$2"; shift 2 ;;
    --exclude) EXCLUDES+=("--exclude" "$2"); shift 2 ;;
    --delete) DELETE=true; shift 1 ;;
    --dry-run) DRY_RUN=true; shift 1 ;;
    --verbose) VERBOSE=true; shift 1 ;;
    --help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

# --- Validation ---
if [ -z "$SOURCE_HOST" ] || [ -z "$TARGET_HOST" ] || [ -z "$SOURCE_USER" ] || [ -z "$TARGET_USER" ]; then
  die "Source/Target host and user are required. See --help."
fi
if [ ${#JOB_PATHS[@]} -eq 0 ]; then
  die "At least one --job-path must be specified."
fi

# SSH Agent Check
if [ -z "$SSH_AUTH_SOCK" ]; then
    log "Warning: SSH_AUTH_SOCK is not set. SSH Agent Forwarding might fail."
    log "Please Ensure 'ssh-agent' is running and keys are added (ssh-add)."
fi

# --- Main Logic ---

# Rsync options
# -a: archive mode
# -v: verbose
# -z: compress
# -R: use relative path names (crucial for preserving directory structure)
RSYNC_OPTS="-avzR -e \"ssh -p $SSH_PORT_TARGET -o StrictHostKeyChecking=no\""

if [ "$DRY_RUN" = true ]; then
  RSYNC_OPTS="$RSYNC_OPTS --dry-run"
fi

if [ "$DELETE" = true ]; then
  RSYNC_OPTS="$RSYNC_OPTS --delete"
fi

# Combine defaults exclusions with user provided exclusions if needed
# Common Jenkins exclusions to avoid massive unneeded transfers
# (User can override or add to these via --exclude, strictly speaking these are additive)
# Adding default excludes consistent with best practices unless user explicitly manages them?
# Let's add them as defaults but allow user to add more.
DEFAULT_EXCLUDES=(
  "--exclude" "workspace/"
  "--exclude" "lastStable"
  "--exclude" "lastSuccessful"
  "--exclude" "nextBuildNumber"
)
# Merge arrays
FULL_EXCLUDES=("${DEFAULT_EXCLUDES[@]}" "${EXCLUDES[@]}")


log "Starting Jenkins job sync process..."
verbose_log "Source: $SOURCE_USER@$SOURCE_HOST"
verbose_log "Target: $TARGET_USER@$TARGET_HOST"
verbose_log "Dry Run: $DRY_RUN"

for job_path in "${JOB_PATHS[@]}"; do
  log "Syncing job path: '$job_path'"

  # IMPORTANT: We need to change directory to the jobs dir on source so -R works correctly
  # relative to the jobs folder.
  # rsync command structure to be executed ON SOURCE:
  # cd /var/jenkins_home/jobs && rsync [opts] [excludes] ./relative/path/to/job user@target:/var/jenkins_home/jobs/

  # Construct the rsync command string safely
  # We construct the array of arguments for rsync first
  
  RSYNC_CMD_STR="rsync $RSYNC_OPTS ${FULL_EXCLUDES[*]} \"./$job_path\" $TARGET_USER@$TARGET_HOST:$TARGET_JENKINS_HOME/jobs/"
  
  # Full remote command
  # 1. cd to source jobs dir
  # 2. Check if job path exists
  # 3. Execute rsync
  
  REMOTE_SCRIPT="
    set -e
    if [ ! -d \"$SOURCE_JENKINS_HOME/jobs/$job_path\" ]; then
       echo \"[REMOTE-ERROR] Source path '$SOURCE_JENKINS_HOME/jobs/$job_path' does not exist.\" >&2
       exit 1
    fi
    cd \"$SOURCE_JENKINS_HOME/jobs\"
    echo \"[REMOTE] Executing: $RSYNC_CMD_STR\"
    $RSYNC_CMD_STR
  "

  verbose_log "Connecting to SOURCE to execute transfer..."
  
  # Execute via SSH with Agent Forwarding (-A)
  # using -t to allocate a tty if needed, but usually better without for automation unless interactive.
  # simple command execution usually doesn't need -t.
  
  ssh -o StrictHostKeyChecking=no -A -p "$SSH_PORT_SOURCE" "$SOURCE_USER@$SOURCE_HOST" "$REMOTE_SCRIPT"

  if [ $? -eq 0 ]; then
     log "Successfully synced '$job_path'."
  else
     die "Failed to sync '$job_path'. Check logs."
  fi

done

log "Sync execution finished."
