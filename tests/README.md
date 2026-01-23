## Test Scripts


### `run_test_copy-jenkins-jobs.sh`

Integration test for `copy-jenkins-jobs-scp.sh`. Spins up Docker containers with Jenkins instances and tests the complete SCP-based job copy workflow including token updates.

**Test Workflow:**
1. Cleanup previous Docker environment
2. Generate SSH keys (source and target)
3. Start Docker containers and wait for Jenkins to be ready
4. Deploy test jobs to source Jenkins (simple and multibranch)
5. Copy jobs to target using `copy-jenkins-jobs-scp.sh`
6. Verify jobs exist on target
7. Update webhook tokens using `updateJenkinsConfigTokens.sh`
8. Verify token updates (both plain-text and encrypted)

**What it tests:**
- Job copying via SCP/tar method
- SSH key authentication
- Multiple job types (simple pipeline and multibranch)
- Job verification on target (filesystem and API)
- Webhook token updates (plain-text and encrypted)

**Run:**
```bash
./run_test_copy-jenkins-jobs.sh
```

### `run_test_sync-jobs-rsync.sh`

Integration test for `copy-jenkins-jobs-rsync.sh`. Tests the complete rsync-based job synchronization workflow with SSH agent forwarding and token updates.

**Test Workflow:**
1. Cleanup previous Docker environment
2. Generate SSH keys and add to SSH agent
3. Start Docker containers and configure SSH access
4. Deploy test jobs to source Jenkins
5. Run dry-run sync to preview changes
6. Run actual sync with `--delete` flag
7. Verify jobs on target
8. Update webhook tokens
9. Verify token updates

**What it tests:**
- Job syncing via rsync
- SSH agent forwarding
- Incremental updates
- Dry-run mode
- Multiple job types
- Webhook token management

**Run:**
```bash
./run_test_sync-jobs-rsync.sh
```

### `run_test-updatetokens.sh`

Focused integration test for `updateJenkinsConfigTokens.sh`. Tests token update functionality in isolation.

**Test Workflow:**
1. Cleanup and setup Docker environment
2. Deploy test jobs with initial tokens
3. Update tokens using `updateJenkinsConfigTokens.sh`
4. Verify token changes (diff, file details, token values)

**What it tests:**
- Token encryption via Jenkins CLI
- Plain-text token replacement (`<token>` for multibranch-scan-webhook-trigger)
- Encrypted token replacement (`<secretToken>` for GitLab plugin)
- Verification of token updates via diff and grep

**Run:**
```bash
./run_test-updatetokens.sh
```

---

# Test output log:
```
➜  ci-copy-jobs git:(main) ✗ ./run_test_sync-jobs-rsync.sh 

--- Cleaning up any previous Docker environment ---

--- Generating SSH keys for test ---
Generating public/private rsa key pair.
Your identification has been saved in ./jenkins_test_key_source
Your public key has been saved in ./jenkins_test_key_source.pub
The key fingerprint is:
SHA256:XXX XXX@MAC-XXX-2.local
The key's randomart image is:
+---[RSA 4096]----+
|     .@=o=.      |
|    +=o*o*o.     |
|   =.++.+.* .    |
|  . E+ +o+ =     |
|   .  o SoB +    |
|       o.* = .   |
|        o + o    |
|         o .     |
|                 |
+----[SHA256]-----+
Generating public/private rsa key pair.
Your identification has been saved in ./jenkins_test_key_target
Your public key has been saved in ./jenkins_test_key_target.pub
The key fingerprint is:
SHA256:XXXXXXX/zo XXX@MAC-XXX-2.local
The key's randomart image is:
+---[RSA 4096]----+
|   o++o.       ..|
|  .+ *o o     . .|
|    * =..o . .  o|
|     . + o. o. o.|
|        S   o.o +|
|       . o = . o+|
|      E   o + .*o|
|       .o. o  +.=|
|        +B+. . o |
+----[SHA256]-----+
SSH keys generated.

--- Starting SSH Agent ---
Agent pid 80627
Identity added: ./jenkins_test_key_source (XXX@MAC-XXX-2.local)
Identity added: ./jenkins_test_key_target (XXX@MAC-XXX-2.local)

--- Building and starting Docker containers ---
[+] Building 11.3s (19/19) FINISHED                                                                                                                                                     
 => [internal] load local bake definitions                                                                                                                                         0.0s
 => => reading from stdin 1.14kB                                                                                                                                                   0.0s
 => [jenkins-source internal] load build definition from Dockerfile                                                                                                                0.0s
 => => transferring dockerfile: 1.21kB                                                                                                                                             0.0s
 => [jenkins-source internal] load metadata for docker.io/jenkins/jenkins:lts                                                                                                      1.4s
 => [auth] jenkins/jenkins:pull token for registry-1.docker.io                                                                                                                     0.0s
 => [jenkins-target internal] load .dockerignore                                                                                                                                   0.0s
 => => transferring context: 2B                                                                                                                                                    0.0s
 => [jenkins-source 1/8] FROM docker.io/jenkins/jenkins:lts@sha256:XXX                                                0.0s
 => => resolve docker.io/jenkins/jenkins:lts@sha256:XXX                                                               0.0s
 => CACHED [jenkins-target 2/8] RUN apt-get update && apt-get install -y openssh-server rsync                                                                                      0.0s
 => CACHED [jenkins-target 3/8] RUN echo 'root:root' | chpasswd                                                                                                                    0.0s
 => CACHED [jenkins-target 4/8] RUN mkdir -p /var/run/sshd                                                                                                                         0.0s
 => CACHED [jenkins-target 5/8] RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config                                                        0.0s
 => CACHED [jenkins-target 6/8] RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config                                                            0.0s
 => CACHED [jenkins-target 7/8] RUN sed -i 's/#StrictModes yes/StrictModes no/' /etc/ssh/sshd_config                                                                               0.0s
 => CACHED [jenkins-target 8/8] RUN echo "#!/bin/bash" > /usr/local/bin/start-jenkins-sshd.sh &&     echo "/usr/sbin/sshd -D &" >> /usr/local/bin/start-jenkins-sshd.sh &&     ec  0.0s
 => [jenkins-source] exporting to docker image format                                                                                                                              9.1s
 => => exporting layers                                                                                                                                                            0.0s
 => => exporting manifest sha256:XXX                                                                                  0.0s
 => => exporting config sha256:XXX                                                                                    0.1s
 => => sending tarball                                                                                                                                                             9.0s
 => [jenkins-target] exporting to docker image format                                                                                                                              9.1s
 => => exporting layers                                                                                                                                                            0.0s
 => => exporting manifest sha256:XXX                                                                                  0.1s
 => => exporting config sha256:XXX                                                                                    0.0s
 => => sending tarball                                                                                                                                                             9.0s
 => importing to docker                                                                                                                                                            0.0s
 => importing to docker                                                                                                                                                            0.0s
 => [jenkins-source] resolving provenance for metadata file                                                                                                                        0.0s
 => [jenkins-target] resolving provenance for metadata file                                                                                                                        0.0s
[+] Running 5/5
 ✔ ci-copy-jobs-jenkins-target   Built                                                                                                                                             0.0s 
 ✔ ci-copy-jobs-jenkins-source   Built                                                                                                                                             0.0s 
 ✔ Network ci-copy-jobs_default  Created                                                                                                                                           0.0s 
 ✔ Container jenkins-source      Started                                                                                                                                           0.6s 
 ✔ Container jenkins-target      Started                                                                                                                                           0.6s 
Containers are starting in the background...

--- Waiting for Jenkins controllers to be available... ---
Waiting for Jenkins on port 8081...
Jenkins on port 8081 is ready.
Waiting for Jenkins on port 8082...
Jenkins on port 8082 is ready.

--- Configuring SSH and creating test job on SOURCE ---
Successfully copied 2.56kB to jenkins-source:/root/.ssh/authorized_keys
Successfully copied 2.56kB to jenkins-target:/root/.ssh/authorized_keys

--- Creating job 'test-sync-job' on jenkins-source ---
Successfully copied 2.56kB to jenkins-source:/var/jenkins_home/jobs/test-sync-job/config.xml

--- Verifying job exists on SOURCE before copy ---
OK: Job 'test-sync-job' found on SOURCE.

--- Running the sync-jobs-rsync.sh script ---
=> Starting Jenkins job sync process...
   [VERBOSE] Source: root@localhost
   [VERBOSE] Target: root@jenkins-target
   [VERBOSE] Dry Run: true
=> Syncing job path: 'test-sync-job'
   [VERBOSE] Connecting to SOURCE to execute transfer...
Warning: Permanently added '[localhost]:2221' (ED25519) to the list of known hosts.
[REMOTE] Executing: rsync -avzR -e ssh -p 22 -o StrictHostKeyChecking=no --dry-run --exclude workspace/ --exclude lastStable --exclude lastSuccessful --exclude nextBuildNumber ./test-sync-job root@jenkins-target:/var/jenkins_home/jobs/
Warning: Permanently added 'jenkins-target' (ED25519) to the list of known hosts.
sending incremental file list
test-sync-job/

sent 139 bytes  received 16 bytes  310.00 bytes/sec
total size is 634  speedup is 4.09 (DRY RUN)
=> Successfully synced 'test-sync-job'.
=> Sync execution finished.
Dry run complete. Now running actual sync...
=> Starting Jenkins job sync process...
   [VERBOSE] Source: root@localhost
   [VERBOSE] Target: root@jenkins-target
   [VERBOSE] Dry Run: false
=> Syncing job path: 'test-sync-job'
   [VERBOSE] Connecting to SOURCE to execute transfer...
[REMOTE] Executing: rsync -avzR -e ssh -p 22 -o StrictHostKeyChecking=no --delete --exclude workspace/ --exclude lastStable --exclude lastSuccessful --exclude nextBuildNumber ./test-sync-job root@jenkins-target:/var/jenkins_home/jobs/
sending incremental file list
test-sync-job/

sent 216 bytes  received 16 bytes  464.00 bytes/sec
total size is 634  speedup is 4.09 (DRY RUN)
=> Successfully synced 'test-sync-job'.
=> Sync execution finished.
Dry run complete. Now running actual sync...
=> Starting Jenkins job sync process...
   [VERBOSE] Source: root@localhost
   [VERBOSE] Target: root@jenkins-target
   [VERBOSE] Dry Run: false
=> Syncing job path: 'test-sync-job'
   [VERBOSE] Connecting to SOURCE to execute transfer...
[REMOTE] Executing: rsync -avzR -e ssh -p 22 -o StrictHostKeyChecking=no --delete --exclude workspace/ --exclude lastStable --exclude lastSuccessful --exclude nextBuildNumber ./test-sync-job root@jenkins-target:/var/jenkins_home/jobs/
sending incremental file list
test-sync-job/

sent 216 bytes  received 16 bytes  464.00 bytes/sec
total size is 634  speedup is 2.73
=> Successfully synced 'test-sync-job'.
=> Sync execution finished.

--- Verifying job on TARGET after sync ---
SUCCESS: Job 'test-sync-job' directory found on TARGET.
SUCCESS: config.xml found in job directory on TARGET.

--- TEST SUCCEEDED! ---

--- Cleaning up ---
[+] Running 3/3
 ✔ Container jenkins-target      Removed                                                                                                                                           0.4s 
 ✔ Container jenkins-source      Removed                                                                                                                                           0.5s 
 ✔ Network ci-copy-jobs_default  Removed                                                                                                                                           0.3s 
Cleanup complete.



```
---

## Utility Scripts

### `updateJenkinsConfigTokens.sh`

This script updates webhook tokens in Jenkins job configuration files. It handles both plain-text tokens (for multibranch-scan-webhook-trigger plugin) and encrypted tokens (for GitLab plugin).

**Features:**
- Encrypts tokens using Jenkins' built-in Secret encryption
- Updates `<token>` elements (plain-text for multibranch webhook triggers)
- Updates `<secretToken>` elements (encrypted for GitLab webhooks)
- Uses `jenkins-cli.jar` for token encryption

**Usage:**
```bash
source ./set-test-env.sh
./updateJenkinsConfigTokens.sh
```

**Environment Variables Required:**
- `MY_NEW_TOKEN` - The new token value to set
- `JENKINS_HOST` - Jenkins URL (e.g., http://localhost:8082)
- `JENKINS_OWNER` - Jenkins username for authentication
- `JENKINS_TOKEN` - Jenkins API token
- `SSH_OPTS` - SSH connection options
- `SSH_USER`, `SSH_HOST` - Remote host credentials
- `JENKINS_HOME` - Jenkins home directory path on remote host

### `set-test-env.sh`

Shared environment configuration and helper functions for all test scripts. This centralizes common configuration to follow the DRY principle.

**Exported Variables:**
- SSH configuration (keys, ports, options)
- Jenkins configuration (home, host, credentials)
- Test job configuration files
- Docker environment paths

**Helper Functions:**
- `log()` - Formatted logging output with visual separators
- `generate_ssh_key_if_needed()` - Generate SSH keys if they don't exist, start SSH agent and add keys
- `cleanup()` - Clean up Docker containers, temporary files, and SSH keys (runs on EXIT via trap)
- `init()` - Build and start Docker containers, wait for Jenkins to be ready, configure SSH access
- `prepareTestJob()` - Deploy a test job configuration to the source Jenkins instance
- `verifyResult()` - Verify job was successfully copied/synced to target Jenkins (checks filesystem and API)
- `verify_token_update()` - Verify webhook tokens were updated correctly (shows diff, file details, and token values)

**Usage:**
```bash
source ./set-test-env.sh
# Now all variables and functions are available
```

---


## Development

All test scripts use the shared `set-test-env.sh` for configuration. To modify test parameters, edit the environment variables in that file.

**Docker Environment:**
- Source Jenkins: `localhost:8081` (SSH port 2221)
- Target Jenkins: `localhost:8082` (SSH port 2222)
- Both run Jenkins LTS with SSH and rsync installed

**Cleanup:**
Test scripts use a `trap cleanup EXIT` to ensure Docker containers are stopped and temporary files are removed even if tests fail.

