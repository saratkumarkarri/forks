#!/bin/bash

set -e

REMOTE_NAME="upstream-ecs"
FOLDER="terraform-aws-ecs"
REPO_URL="https://github.com/terraform-aws-modules/terraform-aws-ecs.git"

if ! git remote | grep -q "$REMOTE_NAME"; then
  echo "Adding remote $REMOTE_NAME..."
  git remote add "$REMOTE_NAME" "$REPO_URL"
else
  echo "Remote $REMOTE_NAME already exists."
fi

if [ -d "$FOLDER" ]; then
  echo "Folder $FOLDER exists. Reinitializing as subtree..."
  git rm -r "$FOLDER"
  git commit -m "Remove $FOLDER to reinitialize as subtree"
fi

echo "Adding $FOLDER as a subtree..."
git subtree add --prefix="$FOLDER" "$REMOTE_NAME" master --squash

echo "To pull latest changes in the future, run:"
echo "git subtree pull --prefix=$FOLDER $REMOTE_NAME master --squash"

# uncomment for pulling latest from upstream
# git subtree pull --prefix=terraform-aws-ecs upstream-ecs master --squash
