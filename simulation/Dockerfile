# Use Rocky Linux 9 (RHEL 9 / 8 / 7 binary compatible enterprise Linux)
FROM rockylinux:9

LABEL maintainer="Antigravity Assistant"
LABEL description="RHEL 7+ Simulation Environment for testing Kerberos Keytab Manager"

# Install MIT Kerberos workstation utilities, bash, and supporting tools
RUN dnf install -y --allowerasing \
    krb5-workstation \
    krb5-libs \
    bash \
    coreutils \
    findutils \
    which \
    procps-ng \
    sudo \
    diffutils \
    vim-minimal \
    && dnf clean all

# Set working directory
WORKDIR /workspace

# Copy setup scripts and main tool
COPY simulation/setup_mock_data.sh /usr/local/bin/setup_mock_data.sh
RUN chmod +x /usr/local/bin/setup_mock_data.sh

# Run setup to initialize mock keytabs inside container
RUN /usr/local/bin/setup_mock_data.sh

# Set environment
ENV TERM=xterm-256color
ENV LANG=en_US.UTF-8

# Default entrypoint
CMD ["/bin/bash"]
