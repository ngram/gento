#!/usr/bin/env bash
# Installs everything the three suites need, so a fresh Codespace can run
# `bundle exec rspec` and `docker build` without further setup.
#
# Safe to re-run by hand if the automatic postCreateCommand failed:
#   bash .devcontainer/setup.sh
set -euo pipefail

trap 'echo; echo "!! setup failed on line $LINENO. Re-run with: bash .devcontainer/setup.sh"; exit 1' ERR

echo "==> environment"
echo "    ruby:   $(command -v ruby || echo MISSING) $(ruby -v 2>/dev/null || true)"
echo "    bundler: $(command -v bundle || echo MISSING)"
echo "    node:   $(command -v node || echo MISSING) $(node -v 2>/dev/null || true)"

# A .ruby-version naming a patch release the image does not carry stops the
# version manager from activating, and then nothing is on PATH — including
# bundler. Fail here with an explanation rather than 20 lines of "not found".
if ! command -v bundle > /dev/null; then
  echo
  echo "!! bundler is not on PATH."
  if [ -f .ruby-version ]; then
    echo "   This repository has a .ruby-version pinning '$(cat .ruby-version)'."
    echo "   If that exact version is not installed in the image, the version"
    echo "   manager cannot activate and no gem executables reach PATH."
    echo "   Delete it (rm .ruby-version), open a NEW terminal, and re-run this script."
  else
    echo "   Check what the image provides: which ruby; ruby -v; gem env"
  fi
  exit 1
fi

echo
echo "==> gem dependencies"
bundle install
bundle config set --local bin bin
bundle binstubs rspec-core rubocop rake --force

echo "==> demo app dependencies"
(
  cd web
  bundle install
  bundle config set --local bin bin
  bundle binstubs rspec-core puma --force
)

echo "==> worker dependencies"
(cd worker && npm ci)

# The intended workflow here is to drive edits through Claude Code rather than
# type them, which matters a great deal when the client is a phone.
echo "==> Claude Code"
npm install -g @anthropic-ai/claude-code || echo "(skipped: install it later with npm i -g @anthropic-ai/claude-code)"

echo
echo "Ready. Try:"
echo "  bundle exec rspec                       # 151 examples"
echo "  docker build -f web/Dockerfile -t gento-web ."
echo "  See doc/codespaces.md for the full walkthrough."
