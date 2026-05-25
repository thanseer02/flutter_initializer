#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# CONFIG
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
# SAFE INPUT
# ------------------------------------------------------------------------------
read_input() {
  local prompt="$1"
  local input=""

  while true; do
    if [[ -t 0 ]]; then
      read -rp "$prompt" input
    else
      read -rp "$prompt" input < /dev/tty
    fi

    [[ -z "$input" ]] && continue
    echo "$input"
    return
  done
}

# ------------------------------------------------------------------------------
# PROMPTS
# ------------------------------------------------------------------------------
prompt_project_name() {
  while true; do
    local value
    value=$(read_input "📦 Project Name (snake_case): ")

    [[ "$value" =~ ^[a-z][a-z0-9_]*$ ]] && {
      PROJECT_NAME="$value"
      break
    }

    log_error "Use lowercase letters, numbers, underscores only"
  done
}

prompt_app_name() {
  APP_NAME=$(read_input "📱 App Name: ")
}

prompt_bundle_id() {
  while true; do
    local value
    value=$(read_input "🆔 Bundle ID (com.company.app): ")

    [[ "$value" =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$ ]] && {
      BUNDLE_ID="$value"
      break
    }

    log_error "Invalid bundle ID"
  done
}

prompt_repo_url() {
  while true; do
    local value
    value=$(read_input "🔗 Git Repo URL: ")

    [[ "$value" =~ ^(git@|https://).+ ]] && {
      REPO_URL="$value"
      break
    }

    log_error "Must start with git@ or https://"
  done
}

prompt_fvm_version() {
  while true; do
    local value
    value=$(read_input "🧩 Flutter Version (e.g. 3.19.0): ")

    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && {
      FVM_VERSION="$value"
      break
    }

    log_error "Invalid version"
  done
}

# ------------------------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------------------------
WORK_DIR=""
cleanup() {
  local exit_code=$?
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
  [[ $exit_code -ne 0 ]] && log_error "Installer failed"
}
trap cleanup EXIT

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
  log_step "Checking dependencies"
  require_cmd git
}

# ------------------------------------------------------------------------------
# FVM / FLUTTER SETUP (NO DART REQUIRED)
# ------------------------------------------------------------------------------
setup_fvm() {
  log_step "Setting up Flutter (via FVM)"

  if ! command -v fvm &>/dev/null; then
    log_warn "FVM not found. Installing..."

    git clone https://github.com/leoafarias/fvm.git "$HOME/.fvm"
    export PATH="$HOME/.fvm/default/bin:$PATH"
  fi

  export PATH="$PATH:$HOME/.fvm/default/bin"

  log_info "Installing Flutter $FVM_VERSION..."
  fvm install "$FVM_VERSION"
  fvm use "$FVM_VERSION" --force
}

# ------------------------------------------------------------------------------
# CLONE TEMPLATE
# ------------------------------------------------------------------------------
clone_template() {
  WORK_DIR="${SCRIPT_DIR}/temp_${PROJECT_NAME}"

  log_step "Cloning template"
  git clone --depth=1 "$TEMPLATE_REPO" "$WORK_DIR"
  rm -rf "$WORK_DIR/.git"
}

# ------------------------------------------------------------------------------
# RENAME PROJECT
# ------------------------------------------------------------------------------
rename_project() {
  log_step "Renaming project"
  cd "$WORK_DIR"

  if sed --version &>/dev/null 2>&1; then
    sed -i "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml
  else
    sed -i '' "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml
  fi

  if command -v dart &>/dev/null; then
    if ! command -v rename &>/dev/null; then
      dart pub global activate rename
    fi

    rename setBundleId --value "$BUNDLE_ID"
    rename setAppName --value "$APP_NAME"
  else
    log_warn "Skipping bundle/app rename (dart not available)"
  fi
}

# ------------------------------------------------------------------------------
# FLUTTER SETUP
# ------------------------------------------------------------------------------
flutter_setup() {
  log_step "Running flutter pub get"
  fvm flutter pub get
}

# ------------------------------------------------------------------------------
# GIT PUSH
# ------------------------------------------------------------------------------
push_repo() {
  log_step "Pushing to Git"

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

  confirm=$(read_input "Continue? (y/n): ")
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