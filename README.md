# Jenkins Job Copier

This repository contains scripts to copy Jenkins jobs from a source controller to a target controller.

## Scripts

1.  **`copy-jenkins-jobs.sh`**: Uses `scp` and `tar` to archive and transfer jobs. Good for simple transfers or when `rsync` is not available.
2.  **`sync-jobs-rsync.sh`**: Uses `rsync` over SSH. Efficient for syncing large jobs or incremental updates. Supports exclusions for build artifacts.

---

## Workflows

### `copy-jenkins-jobs.sh` (SCP Transfer)

Data flows through the admin's machine (`scp -3`).

```mermaid
sequenceDiagram
    autonumber
    participant Local as Admin Laptop
    participant Source as Source Controller
    participant Target as Target Controller

    note over Local, Target: copy-jenkins-jobs.sh (Transfer via Local)

    Local->>Source: SSH: Check if job exists
    Local->>Target: SSH: Check if job exists (skip if present unless --force)
    
    Local->>Source: SSH: Create tarball (mktemp + tar)
    activate Source
    Source-->>Local: archive_path.tar.gz
    deactivate Source

    note right of Local: scp -3 transfers data<br/>Source -> Local -> Target
    Local->>Source: SCP: Read archive
    activate Source
    Local->>Target: SCP: Write archive
    activate Target
    Source-->>Local: Data Stream
    deactivate Source
    Local-->>Target: Data Stream
    deactivate Target

    Local->>Target: SSH: Extract tarball & chown
    Local->>Target: HTTP: Reload Configuration (optional)
    
    Local->>Source: SSH: Cleanup temp files
    Local->>Target: SSH: Cleanup temp files
```

### `sync-jobs-rsync.sh` (Rsync Push)

Data flows directly between controllers. Source authenticates to Target using the Admin's SSH Agent.

```mermaid
sequenceDiagram
    autonumber
    participant Local as Admin Laptop
    participant Source as Source Controller
    participant Target as Target Controller

    note over Local, Target: sync-jobs-rsync.sh (Direct Push using Agent Forwarding)

    note left of Local: SSH Agent has keys<br/>for Source & Target
    
    Local->>Source: SSH -A (Agent Fwd): Connect
    activate Source
    
    note right of Source: Source Authenticates to Target<br/>using Local's Answer
    Source->>Target: SSH: Start rsync server
    activate Target
    
    Source->>Target: RSYNC: Push Data (Delta Transfer)
    Target-->>Source: Acknowledgement
    deactivate Target
    
    Source-->>Local: Exit Status
    deactivate Source
```

## `copy-jenkins-jobs.sh`

This is the main script for copying jobs using tarball archives.

### Requirements

- `bash`, `ssh`, `scp`, `tar`, `gzip`, `curl` must be installed on the machine running the script.
- The source and target controllers must be Linux-based.
- SSH access must be configured from the machine running the script to both Jenkins controllers. The SSH user must have `permissions` to read the Jenkins home directory and write to the target directory.

### Usage

```sh
./copy-jenkins-jobs.sh [OPTIONS]
```

**Required:**
```
  `--source-host <host>`          Source Jenkins controller hostname or IP.
  `--target-host <host>`          Target Jenkins controller hostname or IP.
  `--source-user <user>`          SSH user for the source host.
  `--target-user <user>`          SSH user for the target host.
  `--job-path <path>`             Subpath of the job to copy (e.g., "teamA/job1"). Can be specified multiple times.
  ```

**Optional:**
```
  `--source-jenkins-home <path>`  Path to Jenkins home on the source. (Default: /var/jenkins_home)
  `--target-jenkins-home <path>`  Path to Jenkins home on the target. (Default: /var/jenkins_home)
  `--ssh-port-source <port>`      SSH port for the source host (Default: 22).
  `--ssh-port-target <port>`      SSH port for the target host (Default: 22).
  `--ssh-key-source <path>`       Path to the SSH private key for the source.
  `--ssh-key-target <path>`       Path to the SSH private key for the target.
  `--jenkins-url-target <url>`    URL of the target Jenkins for config reload.
  `--jenkins-user <user>`         Jenkins user for reload authentication.
  `--jenkins-token <token>`       Jenkins API token for reload authentication.
  `--jenkins-owner <user>`        The user/group to own the job files on target. (Default: jenkins)
  `--force`                       Overwrite existing jobs on the target.
  `--dry-run`                     Show what would be done without making changes.
  `--verbose`                     Enable verbose logging.
  `--help`                        Display this help message.
```

### Examples

#### 1. Copy a Single Job

Copies the job located at `/var/jenkins_home/jobs/production-deployment`.

```sh
./copy-jenkins-jobs.sh \
  --source-host jenkins-prod.example.com \
  --target-host jenkins-staging.example.com \
  --source-user admin-user \
  --target-user admin-user \
  --ssh-key-source ~\.ssh/id_rsa_prod \
  --ssh-key-target ~\.ssh/id_rsa_staging \
  --job-path "production-deployment"
```

#### 2. Copy Multiple & Nested Jobs

Copies `nightly-builds` from the root of `jobs/` and `microservice-a` from a nested folder.

```sh
./copy-jenkins-jobs.sh \
  --source-host jenkins-prod.example.com \
  --target-host jenkins-staging.example.com \
  --source-user admin-user \
  --target-user admin-user \
  --job-path "nightly-builds" \
  --job-path "team-alpha/pipelines/microservice-a"
```

#### 3. Force Overwrite and Reload with Authentication

Overwrites the destination job and uses an API token to reload the target controller's configuration.

```sh
./copy-jenkins-jobs.sh \
  --source-host 10.0.1.10 \
  --target-host 10.0.2.20 \
  --source-user jenkins-svc \
  --target-user jenkins-svc \
  --job-path "important-job" \
  --force \
  --jenkins-url-target "https://jenkins.staging.example.com" \
  --jenkins-user "api-user" \
  --jenkins-token "11abcdef1234567890abcdef1234567890ab"
```

#### 4. Dry Run

Preview the operations without making any changes.

```sh
./copy-jenkins-jobs.sh \
  --source-host jenkins-prod.example.com \
  --target-host jenkins-staging.example.com \
  --source-user admin-user \
  --target-user admin-user \
  --job-path "teamA/job1" \
  --job-path "folderX/job2" \
  --dry-run \
  --verbose
```

---

## `sync-jobs-rsync.sh`

This script uses `rsync` over SSH to synchronize jobs. It is more efficient for transfers (incremental) and allows powerful filtering.

### Requirements

- `rsync` must be installed on the **Source** and **Target** controllers.
- **SSH Agent Forwarding**: The script runs locally but executes `rsync` on the Source. You must have `ssh-agent` running locally with keys for both Source and Target loaded.
    - Run `ssh-add ~/.ssh/id_rsa_source` and `ssh-add ~/.ssh/id_rsa_target` before running the script.
- The Source host must be able to connect to the Target host on the SSH port.

### Usage

```sh
./sync-jobs-rsync.sh [OPTIONS]
```

**Required:**
```
  `--source-host <host>`          Source Jenkins controller hostname or IP.
  `--target-host <host>`          Target Jenkins controller hostname or IP.
  `--source-user <user>`          SSH user for the source host.
  `--target-user <user>`          SSH user for the target host.
  `--job-path <path>`             Subpath of the job to sync.
 ```

**Optional:**
```
  `--exclude <pattern>`           Rsync exclude pattern (e.g., 'builds/', 'workspace/').
  `--delete`                      Delete extraneous files on the target (`rsync --delete`).
  `--dry-run`                     Show what would be done.
  `--verbose`                     Enable verbose logging.
  `--ssh-port-source <port>`      (Default: 22)
  `--ssh-port-target <port>`      (Default: 22)
 ```

### Examples

#### 1. Basic Job Sync

Synchronize a job while excluding the workspace and build history (default behavior includes excluding `workspace/`, `lastStable`, etc., but you can add more).

```sh
./sync-jobs-rsync.sh \
  --source-host source.jenkins.example.com --source-user admin \
  --target-host target.jenkins.example.com --target-user admin \
  --job-path "MyFolder/MyJob" \
  --exclude "builds/" \
  --dry-run
```

#### 2. Sync with Delete

This will make the target directory an exact mirror of the source, DELETING any files on the target that are not present on the source (use with caution).

```sh
./sync-jobs-rsync.sh \
  --source-host source.jenkins.example.com --source-user admin \
  --target-host target.jenkins.example.com --target-user admin \
  --job-path "MyProject" \
  --delete
```