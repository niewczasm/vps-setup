#!/bin/bash

# VPS Setup Script
# This script sets up a new user with development tools and Claude Code CLI

set -e  # Exit on any error

echo "Starting VPS setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# 1. Perform system update
log "Performing system update..."
apt update && apt upgrade -y

# 2. Create user named michau
log "Creating user 'michau'..."
if id "michau" &>/dev/null; then
    warn "User 'michau' already exists, skipping creation"
else
    useradd -m -s /bin/bash michau
    log "User 'michau' created successfully"
fi

# 3. Set bash as shell for michau (already done in useradd above)
log "Bash shell set for michau"

# 4. Add michau to sudoers and disable sudo password check
log "Configuring sudo access for michau..."
echo "michau ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/michau
chmod 440 /etc/sudoers.d/michau

# 5. Copy authorized SSH keys from root to michau
log "Copying SSH keys from root to michau..."
if [ -f /root/.ssh/authorized_keys ]; then
    # Create .ssh directory for michau
    sudo -u michau mkdir -p /home/michau/.ssh
    
    # Copy authorized_keys
    cp /root/.ssh/authorized_keys /home/michau/.ssh/authorized_keys
    
    # Set proper ownership and permissions
    chown michau:michau /home/michau/.ssh/authorized_keys
    chmod 600 /home/michau/.ssh/authorized_keys
    chown michau:michau /home/michau/.ssh
    chmod 700 /home/michau/.ssh
    
    log "SSH keys copied and permissions set"
else
    warn "No authorized_keys found in /root/.ssh/, skipping SSH key copy"
fi

# 6. Install NVM as michau user
log "Installing NVM as michau user..."
sudo -u michau bash -c '
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    echo "NVM installation completed"
'

# 7. Source .bashrc and install Node.js LTS as michau
log "Setting up Node.js environment for michau..."
sudo -u michau bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Install latest LTS Node.js
    nvm install --lts
    nvm use --lts
    nvm alias default lts/*
    
    echo "Node.js LTS installed successfully"
    node --version
    npm --version
'

# 8. Install Claude Code CLI as michau
log "Installing Claude Code CLI..."
sudo -u michau bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    npm install -g @anthropic-ai/claude-code
    echo "Claude Code CLI installed successfully"
'

# 9. Add claudeca alias for michau
log "Adding claudeca alias..."
sudo -u michau bash -c '
    echo "" >> ~/.bashrc
    echo "# Claude Code alias" >> ~/.bashrc
    echo "alias claudeca=\"claude --continue --dangerously-allow-everything\"" >> ~/.bashrc
    echo "Alias added to .bashrc"
'

# 10. Harden SSH configuration
log "Hardening SSH configuration..."

# Backup original sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# Disable password authentication
if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
else
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi

# Disable root login
if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
else
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

# Ensure PubkeyAuthentication is enabled
if grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config; then
    sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
else
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
fi

# Test SSH configuration
log "Testing SSH configuration..."
if sshd -t; then
    log "SSH configuration is valid"
    log "Restarting SSH service..."
    systemctl restart sshd
    log "SSH service restarted successfully"
else
    error "SSH configuration test failed! Restoring backup..."
    cp /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S) /etc/ssh/sshd_config
    systemctl restart sshd
    exit 1
fi

# Final verification
log "Running final verification..."
sudo -u michau bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    echo "=== Verification ==="
    echo "User: $(whoami)"
    echo "Node version: $(node --version)"
    echo "NPM version: $(npm --version)"
    echo "Claude Code installed: $(which claude || echo \"Not found in PATH\")"
    echo "Aliases available after next login:"
    grep claudeca ~/.bashrc || echo "Alias not found"
'

log "VPS setup completed successfully!"
echo ""
echo "=== IMPORTANT SECURITY NOTICE ==="
warn "SSH configuration has been hardened:"
warn "- Password authentication is now DISABLED"
warn "- Root login is now DISABLED"
warn "- Only SSH key authentication is allowed"
warn "Make sure you can log in as 'michau' with your SSH key before closing this session!"
echo ""
echo "Next steps:"
echo "1. Test SSH access: ssh michau@your-server-ip (in a new terminal)"
echo "2. Switch to michau user: sudo su - michau"
echo "3. The claudeca alias will be available after sourcing .bashrc or logging in again"
echo "4. Configure Claude Code with your API key if needed"
echo "5. Test the setup: claudeca --help"
echo ""
echo "SSH config backup saved at: /etc/ssh/sshd_config.backup.*"
