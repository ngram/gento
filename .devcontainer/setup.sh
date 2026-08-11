#!/usr/bin/env bash
# Installs everything the three suites need, so a fresh Codespace can run
# `bundle exec rspec` and `docker build` without further setup.
set -euo pipefail

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
echo "  bundle exec rspec                       # 97 examples"
echo "  docker build -f web/Dockerfile -t slidescraper-web ."
echo "  See docs/codespaces.md for the full walkthrough."
