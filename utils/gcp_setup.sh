#!/bin/bash

set -e

HELPER_PATH="./gcp/github-app-credential-helper"
INSTALL_PATH="/usr/local/bin/github-app-credential-helper"
SETUP_SCRIPT="./gcp/setup.sh"

# Ensure the GitHub App credential helper script exists
if [[ ! -f "$HELPER_PATH" ]]; then
  echo "Error: $HELPER_PATH not found!"
  exit 1
fi

# Copy the credential helper script to /usr/local/bin
cp "$HELPER_PATH" "$INSTALL_PATH"

# Make it executable
chmod +x "$INSTALL_PATH"

# Set up Git to use the credential helper
git config --global credential.helper "$INSTALL_PATH"

echo "GitHub App Credential Helper installed successfully!"

# Ensure the setup script exists before executing
if [[ ! -f "$SETUP_SCRIPT" ]]; then
  echo "Error: $SETUP_SCRIPT not found!"
  exit 1
fi

# Run the setup script
echo "Running setup script..."
chmod +x "$SETUP_SCRIPT"
"$SETUP_SCRIPT"

echo "Setup script executed successfully!"

