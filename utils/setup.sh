#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script runs from the home directory
cd "$HOME"

echo "Updating package lists..."
sudo apt-get update

echo "Installing required packages..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    build-essential \
    make \
    git

echo "Installing Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "Adding Docker repository to Apt sources..."
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Updating package lists after adding Docker repo..."
sudo apt-get update

echo "Installing Docker Engine..."
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "Adding current user to the docker group..."
sudo usermod -aG docker "$USER"

echo "Starting a new shell with updated group membership..."
# ---------------------------------------------------------------------
# Everything in this heredoc runs in a subshell with the 'docker' group
# ---------------------------------------------------------------------
newgrp docker <<EOF

echo "Checking if Rust is installed..."
if ! command -v rustc &> /dev/null
then
    echo "Rust not found, installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y
    source "\$HOME/.cargo/env"
else
    echo "Rust is already installed."
fi

echo "Installing 'cross' via cargo..."
cargo install cross --git https://github.com/cross-rs/cross

echo "Returning to the home directory..."
cd ~

# --------------------- FOUNDRY ---------------------
echo "Installing Foundry..."
curl -L https://foundry.paradigm.xyz | bash

# Add Foundry to PATH in the current shell so 'foundryup' is available immediately
export PATH="\$HOME/.foundry/bin:\$PATH"

foundryup

# --------------------- BUN ---------------------
echo "Installing Bun..."
sudo apt update
sudo apt install -y unzip
curl -fsSL https://bun.sh/install | bash
# Reload bashrc to make bun available (if Bun's script added lines)
source "\$HOME/.bashrc"

# --------------------- POSTGRES ---------------------
echo "Installing and configuring PostgreSQL..."
sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Update port to 5433 in PostgreSQL config
sudo sed -i 's/^port = 5432/port = 5433/' /etc/postgresql/*/main/postgresql.conf
sudo systemctl restart postgresql

# Set up database and user
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" \
                      -c "DROP DATABASE IF EXISTS postman_db;" \
                      -c "CREATE DATABASE postman_db;" \
                      -c "GRANT ALL PRIVILEGES ON DATABASE postman_db TO postgres;"

# --------------------- PNPM ---------------------
echo "Installing PNPM..."
curl -fsSL https://get.pnpm.io/install.sh | sh -
source "\$HOME/.bashrc"

# --------------------- NVM & NODE 20 ---------------------
echo "Installing NVM and Node.js (version 20)..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Load NVM into the current shell
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"

nvm install 20

# --------------------- JQ ---------------------
echo "Installing JQ..."
sudo apt install -y jq

# --------------------- TS-NODE ---------------------
echo "Installing ts-node..."
sudo apt install -y ts-node

# --------------------- HARDHAT & TYPESCRIPT ---------------------
echo "Installing global Hardhat and TypeScript..."
npm install -g hardhat
npm install -g typescript

# --------------------- t1 & TDEX ---------------------
echo "Cloning t1 stack and TDEX"
git clone https://github.com/t1protocol/t1
git clone https://github.com/t1protocol/postman
git clone https://github.com/t1protocol/tdex

echo "GitHub repos cloned successfully using Workload Identity Federation!"

EOF
# -----------------------------------------------------
# Exiting 'newgrp docker' shell; returning to original
# -----------------------------------------------------

echo "Setup complete. Please log out and log back in for group changes to take effect."
