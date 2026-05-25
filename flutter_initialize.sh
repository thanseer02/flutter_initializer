#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# CONSTANTS
# ------------------------------------------------------------------------------
TEMPLATE_REPO="git@github.com:YOUR_USERNAME/flutter_mvvm_template.git"
SCRIPT_DIR="$(pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
log_success() { echo -e "${GREEN}✅ $*${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
log_error()   { echo -e "${RED}❌ $*${RESET}" >&2; }
log_step()    { echo -e "\n${BOLD}── $* ${RESET}"; }

# ------------------------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------------------------
WORK_DIR=""
cleanup() {
  local exit_code=$?
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    log_warn "Cleaning up: $WORK_DIR"
    rm -rf "$WORK_DIR"
  fi
  if [[ $exit_code -ne 0 ]]; then
    log_error "Installer failed (exit code: $exit_code)"
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# PROMPTS (FIXED with /dev/tty)
# ------------------------------------------------------------------------------
prompt_project_name() {
  while true; do
    read -rp "📦 Project Name (snake_case): " value < /dev/tty
    [[ "$value" =~ ^[a-z][a-z0-9_]*$ ]] && break
    log_error "Invalid. Use lowercase + underscores only."
  done
  PROJECT_NAME="$value"
}

prompt_app_name() {
  while true; do
    read -rp "📱 App Name: " value < /dev/tty
    [[ -n "$value" ]] && break
    log_error "App name cannot be empty."
  done
  APP_NAME="$value"
}

prompt_bundle_id() {
  while true; do
    read -rp "🆔 Bundle ID (com.company.app): " value < /dev/tty
    [[ "$value" =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$ ]] && break
    log_error "Invalid bundle ID."
  done
  BUNDLE_ID="$value"
}

prompt_repo_url() {
  while true; do
    read -rp "🔗 Git Repo URL: " value < /dev/tty
    [[ "$value" =~ ^(git@|https://).+ ]] && break
    log_error "Invalid repo URL."
  done
  REPO_URL="$value"
}

prompt_fvm_version() {
  while true; do
    read -rp "🧩 Flutter Version (e.g. 3.19.0): " value < /dev/tty
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && break
    log_error "Invalid version."
  done
  FVM_VERSION="$value"
}

# ------------------------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------------------------
require_cmd() {
  command -v "$1" &>/dev/null || {
    log_error "$1 not installed"
    exit 1
  }
}

check_dependencies() {
  log_step "🔍 Checking dependencies"
  require_cmd git
  require_cmd dart
}

# ------------------------------------------------------------------------------
# FVM
# ------------------------------------------------------------------------------
setup_fvm() {
  log_step "⚙️ Setting up FVM"

  if ! command -v fvm &>/dev/null; then
    log_warn "Installing FVM..."
    dart pub global activate fvm
    export PATH="$PATH:$HOME/.pub-cache/bin"
  fi

  fvm install "$FVM_VERSION" --skip-pub-get
  fvm use "$FVM_VERSION" --force
}

# ------------------------------------------------------------------------------
# CLONE TEMPLATE
# ------------------------------------------------------------------------------
clone_template() {
  WORK_DIR="${SCRIPT_DIR}/temp_${PROJECT_NAME}"

  log_step "📥 Cloning template"
  git clone --depth=1 "$TEMPLATE_REPO" "$WORK_DIR"
  rm -rf "$WORK_DIR/.git"
}

# ------------------------------------------------------------------------------
# RENAME PROJECT
# ------------------------------------------------------------------------------
rename_project() {
  log_step "📦 Renaming project"

  cd "$WORK_DIR"

  sed -i "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml || \
  sed -i '' "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml

  if ! command -v rename &>/dev/null; then
    dart pub global activate rename
  fi

  rename setBundleId --value "$BUNDLE_ID"
  rename setAppName --value "$APP_NAME"
}

# ------------------------------------------------------------------------------
# FLUTTER SETUP
# ------------------------------------------------------------------------------
flutter_setup() {
  log_step "📦 Installing dependencies"
  fvm flutter pub get
}

# ------------------------------------------------------------------------------
# GIT PUSH
# ------------------------------------------------------------------------------
push_repo() {
  log_step "🚀 Pushing to GitHub"

  git init
  git add .
  git commit -m "Initial commit"
  git branch -M main
  git remote add origin "$REPO_URL"

  git push -u origin main
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
  clear
  echo -e "${BOLD}🚀 Flutter Project Initializer${RESET}"
  printf '=%.0s' {1..50}; echo ""

  prompt_project_name
  prompt_app_name
  prompt_bundle_id
  prompt_repo_url
  prompt_fvm_version

  echo ""
  echo -e "${YELLOW}Confirm:${RESET}"
  echo "Project: $PROJECT_NAME"
  echo "App: $APP_NAME"
  echo "Bundle: $BUNDLE_ID"
  echo "Repo: $REPO_URL"
  echo "Flutter: $FVM_VERSION"

  read -rp "Continue? (y/n): " confirm < /dev/tty
  [[ "$confirm" != "y" ]] && exit 0

  check_dependencies
  setup_fvm
  clone_template
  rename_project
  flutter_setup
  push_repo

  echo ""
  log_success "🎉 Done!"
  echo "👉 git clone $REPO_URL"
}

main "$@"