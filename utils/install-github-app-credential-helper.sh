#!/bin/bash

set -e

HELPER_SCRIPT="github-app-credential-helper"
TARGET_PATH="/usr/local/bin/github-app-credential-helper"

echo "Copying $HELPER_SCRIPT to $TARGET_PATH..."
sudo cp "$HELPER_SCRIPT" "$TARGET_PATH"

echo "Making $TARGET_PATH executable..."
sudo chmod +x "$TARGET_PATH"

echo "Configuring Git system-wide to use $TARGET_PATH as credential helper..."
sudo git config --system credential.helper "!\"$TARGET_PATH\""

echo "Done. System-wide Git credential helper is now set to $TARGET_PATH."
