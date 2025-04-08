#!/bin/bash

set -e
# version --branch v2.10.2

REMOTE_NAME="upstream-route53"
FOLDER="terraform-aws-route53"
REPO_URL="https://github.com/terraform-aws-modules/terraform-aws-route53.git"

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
# git subtree pull --prefix=terraform-aws-route53 upstream-route53 master --squash
