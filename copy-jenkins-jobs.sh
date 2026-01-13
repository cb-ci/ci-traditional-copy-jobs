#!/bin/bash
#
# Copies Jenkins jobs from a SOURCE controller to a TARGET controller.
#
# Assumptions:
# - Controllers are Linux-based.
# - ssh, scp, tar, gzip, curl, and standard shell utilities are available on the
#   machine running this script and on the target/source hosts.
# - SSH access (ideally key-based) is configured between the machine running
#   this script and both SOURCE and TARGET hosts.
# - The SSH users on SOURCE and TARGET have sufficient permissions to read the
#   Jenkins job directories and write/create directories in the target
#   Jenkins home.

set -Eeo pipefail

# --- Default Configuration ---
SOURCE_JENKINS_HOME="/var/jenkins_home"
TARGET_JENKINS_HOME="/var/jenkins_home"
SSH_PORT_SOURCE="2221"
SSH_PORT_TARGET="2222"
JENKINS_OWNER="jenkins"
DRY_RUN=false
VERBOSE=false
FORCE=false
JOB_PATHS=()

# --- Script self-awareness ---
SCRIPT_NAME=$(basename "$0")
TEMP_FILES_SOURCE=()
TEMP_FILES_TARGET=()

# --- Logging and Cleanup ---
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

cleanup() {
  log "Cleaning up temporary files..."
  if [ ${#TEMP_FILES_SOURCE[@]} -gt 0 ]; then
    verbose_log "Removing temp files on SOURCE: ${TEMP_FILES_SOURCE[*]}"
    # shellcheck disable=SC2086
    ssh $SSH_OPTS_SOURCE "$SOURCE_USER@$SOURCE_HOST" "rm -f ${TEMP_FILES_SOURCE[*]}" || log "Warning: Failed to clean up on source."
  fi
  if [ ${#TEMP_FILES_TARGET[@]} -gt 0 ]; then
    verbose_log "Removing temp files on TARGET: ${TEMP_FILES_TARGET[*]}"
    # shellcheck disable=SC2086
    ssh $SSH_OPTS_TARGET "$TARGET_USER@$TARGET_HOST" "rm -f ${TEMP_FILES_TARGET[*]}" || log "Warning: Failed to clean up on target."
  fi
  log "Cleanup complete."
}

trap cleanup EXIT

# --- Usage Information ---
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] 

Copies Jenkins jobs from a source to a target controller using ssh/scp/tar.

Required:
  --source-host <host>          Source Jenkins controller hostname or IP.
  --target-host <host>          Target Jenkins controller hostname or IP.
  --source-user <user>          SSH user for the source host.
  --target-user <user>          SSH user for the target host.
  --job-path <path>             Subpath of the job to copy (e.g., "teamA/job1").
                                Can be specified multiple times.

Optional:
  --source-jenkins-home <path>  Path to Jenkins home on the source.
                                (Default: /var/jenkins_home)
  --target-jenkins-home <path>  Path to Jenkins home on the target.
                                (Default: /var/jenkins_home)
  --ssh-port-source <port>      SSH port for the source host (Default: 22).
  --ssh-port-target <port>      SSH port for the target host (Default: 22).
  --ssh-key-source <path>       Path to the SSH private key for the source.
  --ssh-key-target <path>       Path to the SSH private key for the target.
  --jenkins-url-target <url>    URL of the target Jenkins for config reload.
  --jenkins-user <user>         Jenkins user for reload authentication.
  --jenkins-token <token>       Jenkins API token for reload authentication.
  --jenkins-owner <user>        The user/group to own the job files on target.
                                (Default: jenkins)
  --force                       Overwrite existing jobs on the target.
  --dry-run                     Show what would be done without making changes.
  --verbose                     Enable verbose logging.
  --help                        Display this help message.
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
    --ssh-key-source) SSH_KEY_SOURCE="$2"; shift 2 ;;
    --ssh-key-target) SSH_KEY_TARGET="$2"; shift 2 ;;
    --jenkins-url-target) JENKINS_URL_TARGET="$2"; shift 2 ;;
    --jenkins-user) JENKINS_USER="$2"; shift 2 ;;
    --jenkins-token) JENKINS_TOKEN="$2"; shift 2 ;;
    --jenkins-owner) JENKINS_OWNER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift 1 ;;
    --verbose) VERBOSE=true; shift 1 ;;
    --force) FORCE=true; shift 1 ;;
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
for path in "${JOB_PATHS[@]}"; do
  if [[ "$path" == *".."* ]] || [[ "$path" == /* ]]; then
    die "Job path '$path' is invalid. It cannot contain '..' or start with '/'."
  fi
done
if [ -n "$JENKINS_URL_TARGET" ] && { [ -n "$JENKINS_USER" ] || [ -n "$JENKINS_TOKEN" ]; } && ! { [ -n "$JENKINS_USER" ] && [ -n "$JENKINS_TOKEN" ]; }; then
    die "Both --jenkins-user and --jenkins-token must be provided for authenticated reload."
fi

# --- Configure SSH/SCP commands ---
SSH_OPTS_SOURCE="-p $SSH_PORT_SOURCE"
SCP_OPTS_SOURCE="-P $SSH_PORT_SOURCE"
if [ -n "$SSH_KEY_SOURCE" ]; then
  SSH_OPTS_SOURCE="$SSH_OPTS_SOURCE -i $SSH_KEY_SOURCE"
  SCP_OPTS_SOURCE="$SCP_OPTS_SOURCE -i $SSH_KEY_SOURCE"
fi

SSH_OPTS_TARGET="-p $SSH_PORT_TARGET"
SCP_OPTS_TARGET="-P $SSH_PORT_TARGET"
if [ -n "$SSH_KEY_TARGET" ]; then
  SSH_OPTS_TARGET="$SSH_OPTS_TARGET -i $SSH_KEY_TARGET"
  SCP_OPTS_TARGET="$SCP_OPTS_TARGET -i $SSH_KEY_TARGET"
fi

# --- Main Logic ---
log "Starting Jenkins job copy process..."
verbose_log "Dry Run: $DRY_RUN"
verbose_log "Force Overwrite: $FORCE"

COPIED_COUNT=0
SKIPPED_COUNT=0

for job_path in "${JOB_PATHS[@]}"; do
  log "Processing job path: '$job_path'"
  
  full_source_path="$SOURCE_JENKINS_HOME/jobs/$job_path"
  full_target_path="$TARGET_JENKINS_HOME/jobs/$job_path"
  target_parent_dir=$(dirname "$full_target_path")

  # 1. Verify job exists on SOURCE
  verbose_log "Verifying source path: $SOURCE_USER@$SOURCE_HOST:$full_source_path"
  # shellcheck disable=SC2086
  if ! ssh $SSH_OPTS_SOURCE "$SOURCE_USER@$SOURCE_HOST" "test -d '$full_source_path'"; then
    log "Warning: Source job directory not found: '$full_source_path'. Skipping."
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  # 2. Check if job exists on TARGET
  verbose_log "Verifying target path: $TARGET_USER@$TARGET_HOST:$full_target_path"
  # shellcheck disable=SC2086
  if ssh $SSH_OPTS_TARGET "$TARGET_USER@$TARGET_HOST" "test -d '$full_target_path'"; then
    if [ "$FORCE" = false ]; then
      log "Warning: Job '$job_path' already exists on target. Use --force to overwrite. Skipping."
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      continue
    else
      log "Job '$job_path' exists on target, but --force is set. Proceeding to overwrite."
    fi
  fi

  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would copy '$job_path' from $SOURCE_HOST to $TARGET_HOST"
    COPIED_COUNT=$((COPIED_COUNT + 1))
    continue
  fi

  # --- Execute Copy ---
  # 3. Create archive on SOURCE
  # Using mktemp to create a secure temporary file name for the archive
  # shellcheck disable=SC2086
  tmp_archive_source=$(ssh $SSH_OPTS_SOURCE "$SOURCE_USER@$SOURCE_HOST" "mktemp -u")
  if [ -z "$tmp_archive_source" ]; then
      die "Failed to create a temporary file name on source host."
  fi
  TEMP_FILES_SOURCE+=("$tmp_archive_source.tar.gz")

  log "Creating archive on source..."
  # The tar command changes directory to preserve the relative path in the archive
  # -p flag preserves permissions
  # shellcheck disable=SC2086
  ssh $SSH_OPTS_SOURCE "$SOURCE_USER@$SOURCE_HOST" \
    "tar -czpf '$tmp_archive_source.tar.gz' -C '$(dirname "$full_source_path")' '$(basename "$job_path")'"
  verbose_log "Source archive created: $tmp_archive_source.tar.gz"
  set -x
  # 4. Transfer archive to TARGET
  # shellcheck disable=SC2086
  tmp_archive_target=$(ssh $SSH_OPTS_TARGET "$TARGET_USER@$TARGET_HOST" "mktemp -u")
  if [ -z "$tmp_archive_target" ]; then
      die "Failed to create a temporary file name on target host."
  fi
  TEMP_FILES_TARGET+=("$tmp_archive_target.tar.gz")

  log "Transferring archive to target..."
  # shellcheck disable=SC2086

 # scp $SCP_OPTS_SOURCE $SCP_OPTS_TARGET "$SOURCE_USER@$SOURCE_HOST:'$tmp_archive_source.tar.gz'" \
 #   "$TARGET_USER@$TARGET_HOST:'$tmp_archive_target.tar.gz'"
  scp -3 -i ./jenkins_test_key \
      scp://$SOURCE_USER@$SOURCE_HOST:$SSH_PORT_SOURCE//$tmp_archive_source.tar.gz \
      scp://$TARGET_USER@$TARGET_HOST:$SSH_PORT_TARGET//$tmp_archive_target.tar.gz
  verbose_log "Archive transferred to: $tmp_archive_target.tar.gz"

  # 5. Extract on TARGET and set permissions
  log "Extracting archive on target..."
  # shellcheck disable=SC2086
  ssh $SSH_OPTS_TARGET "$TARGET_USER@$TARGET_HOST" \
    "mkdir -p '$target_parent_dir' && \
     tar -xzpf '$tmp_archive_target.tar.gz' -C '$target_parent_dir' && \
     chown -R '$JENKINS_OWNER:$JENKINS_OWNER' '$full_target_path'"
  
  log "Successfully copied job '$job_path'."
  COPIED_COUNT=$((COPIED_COUNT + 1))
done

log "--------------------------------------------------"
log "Copy process finished."
log "Summary: $COPIED_COUNT job(s) copied, $SKIPPED_COUNT job(s) skipped."
log "--------------------------------------------------"

# --- 7. Reload Jenkins Configuration ---
if [ $COPIED_COUNT -gt 0 ] && [ "$DRY_RUN" = false ] && [ -n "$JENKINS_URL_TARGET" ]; then
  log "Attempting to reload Jenkins configuration from disk on target..."
  
  CURL_OPTS=("-s" "-X" "POST")
  if [ -n "$JENKINS_USER" ] && [ -n "$JENKINS_TOKEN" ]; then
      verbose_log "Using authentication for Jenkins reload."
      CURL_OPTS+=("--user" "$JENKINS_USER:$JENKINS_TOKEN")
      
      # Fetch CSRF crumb if protection is enabled
      CRUMB_URL="${JENKINS_URL_TARGET}/crumbIssuer/api/json"
      verbose_log "Fetching CSRF crumb from $CRUMB_URL"
      
      # Use sed to parse JSON to avoid dependency on jq
      CRUMB_DATA=$(curl "${CURL_OPTS[@]}" "$CRUMB_URL")
      if [[ "$CRUMB_DATA" == *"\"crumbRequestField\":"* ]]; then
          CRUMB_HEADER=$(echo "$CRUMB_DATA" | sed -n 's/.*\"crumbRequestField\":\"\([^\"]*\)\".*/\1/p')
          CRUMB_VALUE=$(echo "$CRUMB_DATA" | sed -n 's/.*\"crumb\":\"\([^\"]*\)\".*/\1/p')
          
          if [ -n "$CRUMB_HEADER" ] && [ -n "$CRUMB_VALUE" ]; then
              verbose_log "CSRF crumb found. Using header: $CRUMB_HEADER"
              CURL_OPTS+=("-H" "$CRUMB_HEADER:$CRUMB_VALUE")
          else
              log "Warning: Could not parse CSRF crumb from response. Reload might fail."
          fi
      else
        verbose_log "CSRF protection does not seem to be enabled. Proceeding without crumb."
      fi
  fi
  
  RELOAD_URL="${JENKINS_URL_TARGET}/reload"
  verbose_log "Posting to $RELOAD_URL"
  
  HTTP_STATUS=$(curl "${CURL_OPTS[@]}" --write-out "%{http_code}" --output /dev/null "$RELOAD_URL")
  
  if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
    log "Successfully triggered configuration reload on target Jenkins (HTTP $HTTP_STATUS)."
  else
    log "Warning: Failed to trigger configuration reload. Jenkins returned HTTP status $HTTP_STATUS."
    log "You may need to manually reload configuration via the Jenkins UI ('Manage Jenkins' -> 'Reload Configuration from Disk')."
  fi

elif [ $COPIED_COUNT -gt 0 ] && [ "$DRY_RUN" = false ]; then
  log "No --jenkins-url-target provided. Please manually reload configuration:"
  log "1. Go to your Jenkins UI -> Manage Jenkins."
  log "2. Click 'Reload Configuration from Disk'."
fi
