#!/usr/bin/env bash
set -euo pipefail

# 01_install_system_deps.sh
# Installs R, PostgreSQL 16, and OpenJDK via Homebrew.
#
# OpenJDK is not needed until Phase 2 (Synthea is a Java application),
# but it's a one-line install so we get it out of the way now.
# It's keg-only (Homebrew won't put it on PATH by default, since macOS
# ships its own Java stub) so we add it to PATH ourselves and treat a
# missing `java` command as informational, not fatal, at this stage.

echo "==> Installing R (official CRAN build via Homebrew cask)"
brew install --cask r

echo "==> Installing PostgreSQL 16"
brew install postgresql@16
brew link --overwrite --force postgresql@16

echo "==> Installing OpenJDK (used later by Synthea in Phase 2)"
brew install openjdk

ZSHRC="$HOME/.zshrc"
JAVA_PATH_LINE='export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"'
if ! grep -qF "$JAVA_PATH_LINE" "$ZSHRC" 2>/dev/null; then
  echo "$JAVA_PATH_LINE" >> "$ZSHRC"
  echo "==> Added OpenJDK to PATH in ~/.zshrc (takes effect in new terminal tabs)"
fi

echo "==> Starting PostgreSQL as a background service"
brew services start postgresql@16

echo ""
echo "==> Installed versions:"
R --version | head -1
psql --version

if /opt/homebrew/opt/openjdk/bin/java -version >/dev/null 2>&1; then
  echo "✔ Java available"
else
  echo "… Java installed, PATH updated — not required until Phase 2, safe to ignore for now"
fi

echo ""
echo "==> Note the R binary path below — you'll need it for VS Code:"
which R

echo ""
echo "==> Done. Proceed to 02_init_postgres.sh"
