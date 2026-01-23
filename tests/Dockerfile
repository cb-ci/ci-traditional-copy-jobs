# Dockerfile to create a Jenkins image with SSH enabled
FROM jenkins/jenkins:lts

# Switch to root to install packages
USER root

# Install OpenSSH Server
RUN apt-get update && apt-get install -y openssh-server rsync

# Set root password to "Docker!" (CHANGE THIS for production!)
RUN echo 'root:root' | chpasswd

# Configure SSH
RUN mkdir -p /var/run/sshd
# Allow root login via SSH key. In a real-world scenario, you'd create a non-root user.
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/#StrictModes yes/StrictModes no/' /etc/ssh/sshd_config

# Create a startup script to run both sshd and jenkins
RUN echo "#!/bin/bash" > /usr/local/bin/start-jenkins-sshd.sh && \
    echo "/usr/sbin/sshd -D &" >> /usr/local/bin/start-jenkins-sshd.sh && \
    echo "exec /usr/bin/tini -- /usr/local/bin/jenkins.sh" >> /usr/local/bin/start-jenkins-sshd.sh && \
    chmod +x /usr/local/bin/start-jenkins-sshd.sh

# Expose SSH port
EXPOSE 22

# Entrypoint is our new startup script
ENTRYPOINT ["/usr/local/bin/start-jenkins-sshd.sh"]
