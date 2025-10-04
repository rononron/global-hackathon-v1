#!/bin/bash
# Simple Git Commit Script for Hackathon Projects

# Stop on first error
set -e

# 1️⃣  Commit message: take argument or use timestamp
if [ -z "$1" ]; then
  MESSAGE="Auto commit - $(date)"
else
  MESSAGE="$1"
fi

# 2️⃣  Add all changes
git add .

# 3️⃣  Commit changes
git commit -m "$MESSAGE"

# 4️⃣  Push to origin/main
git push origin main

echo "✅ Commit pushed successfully: '$MESSAGE'"

