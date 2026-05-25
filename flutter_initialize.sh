#!/usr/bin/env bash
# ==============================================================================
# Flutter Project Installer
# Usage: bash install.sh <repo_url> <project_name> <app_name> <bundle_id> <fvm_version>
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# CONSTANTS
# ------------------------------------------------------------------------------
readonly TEMPLATE_REPO="git@github.com:YOUR_USERNAME/flutter_mvvm_template.git"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
log_success() { echo -e "${GREEN}✅ $*${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
log_error()   { echo -e "${RED}❌ $*${RESET}" >&2; }
log_step()    { echo -e "\n${BOLD}── $* ${RESET}"; }

# ------------------------------------------------------------------------------
# USAGE
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}Flutter Project Installer${RESET}
$(printf '=%.0s' {1..50})

${BOLD}Usage:${RESET}
  bash install.sh <repo_url> <project_name> <app_name> <bundle_id> <fvm_version>

${BOLD}Arguments:${RESET}
  repo_url        Target Git remote URL (SSH or HTTPS)
  project_name    Dart package name (snake_case, e.g. my_app)
  app_name        Display name shown on device (e.g. "My App")
  bundle_id       Reverse-domain bundle ID (e.g. com.company.myapp)
  fvm_version     Flutter version managed by FVM (e.g. 3.19.0)

${BOLD}Example:${RESET}
  bash install.sh git@github.com:acme/my_app.git my_app "My App" com.acme.myapp 3.19.0

EOF
}

# ------------------------------------------------------------------------------
# CLEANUP (runs on any exit via trap)
# ------------------------------------------------------------------------------
WORK_DIR=""

cleanup() {
  local exit_code=$?
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    log_warn "Cleaning up temporary directory: $WORK_DIR"
    rm -rf "$WORK_DIR"
  fi
  if [[ $exit_code -ne 0 ]]; then
    log_error "Installer failed (exit code: $exit_code). See errors above."
  fi
}

trap cleanup EXIT

# ------------------------------------------------------------------------------
# INPUT VALIDATION
# ------------------------------------------------------------------------------
validate_inputs() {
  local repo_url="$1"
  local project_name="$2"
  local app_name="$3"
  local bundle_id="$4"
  local fvm_version="$5"

  local errors=0

  # repo_url: basic SSH or HTTPS pattern
  if [[ ! "$repo_url" =~ ^(git@|https://).+ ]]; then
    log_error "repo_url must be a valid SSH (git@...) or HTTPS (https://...) URL. Got: '$repo_url'"
    ((errors++))
  fi

  # project_name: Dart package name rules (lowercase, underscores, no leading digits)
  if [[ ! "$project_name" =~ ^[a-z][a-z0-9_]*$ ]]; then
    log_error "project_name must be a valid Dart package name (lowercase, underscores only, no leading digit). Got: '$project_name'"
    ((errors++))
  fi

  # app_name: non-empty
  if [[ -z "$app_name" ]]; then
    log_error "app_name cannot be empty."
    ((errors++))
  fi

  # bundle_id: reverse-domain format
  if [[ ! "$bundle_id" =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){1,}$ ]]; then
    log_error "bundle_id must follow reverse-domain format (e.g. com.company.app). Got: '$bundle_id'"
    ((errors++))
  fi

  # fvm_version: semver-like
  if [[ ! "$fvm_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    log_error "fvm_version must be a valid semver version (e.g. 3.19.0). Got: '$fvm_version'"
    ((errors++))
  fi

  if [[ $errors -gt 0 ]]; then
    usage
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# DEPENDENCY CHECKS
# ------------------------------------------------------------------------------
require_cmd() {
  local cmd="$1"
  local install_hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: '$cmd'"
    [[ -n "$install_hint" ]] && log_info "Install hint: $install_hint"
    exit 1
  fi
}

check_dependencies() {
  log_step "Checking system dependencies"
  require_cmd git   "https://git-scm.com/downloads"
  require_cmd dart  "Install Flutter SDK: https://docs.flutter.dev/get-started/install"
  log_success "All required system dependencies found."
}

# ------------------------------------------------------------------------------
# FVM SETUP
# ------------------------------------------------------------------------------
setup_fvm() {
  local fvm_version="$1"

  log_step "Setting up FVM"

  if ! command -v fvm &>/dev/null; then
    log_warn "FVM not found. Installing via dart pub global..."
    dart pub global activate fvm
  fi

  # Ensure pub-cache bin is on PATH for this session
  local pub_cache_bin
  pub_cache_bin="$(dart pub global run --help 2>/dev/null; dart pub cache path 2>/dev/null || echo "$HOME/.pub-cache")/bin"
  export PATH="$PATH:$pub_cache_bin"

  if ! command -v fvm &>/dev/null; then
    log_error "FVM installation failed or not on PATH. Add '${pub_cache_bin}' to your PATH and retry."
    exit 1
  fi

  log_info "Installing Flutter $fvm_version via FVM (this may take a while)..."
  fvm install "$fvm_version" --skip-pub-get
  fvm use "$fvm_version" --force
  log_success "FVM set to Flutter $fvm_version."
}

# ------------------------------------------------------------------------------
# CLONE TEMPLATE
# ------------------------------------------------------------------------------
clone_template() {
  local work_dir="$1"

  log_step "Cloning template repository"

  if [[ -d "$work_dir" ]]; then
    log_error "Directory '$work_dir' already exists. Remove it and retry."
    exit 1
  fi

  git clone --depth=1 "$TEMPLATE_REPO" "$work_dir"

  # Scrub template git history entirely
  rm -rf "$work_dir/.git"

  log_success "Template cloned to '$work_dir'."
}

# ------------------------------------------------------------------------------
# RENAME PROJECT
# ------------------------------------------------------------------------------
rename_project() {
  local project_name="$1"
  local app_name="$2"
  local bundle_id="$3"

  log_step "Renaming project"

  # ── pubspec.yaml ──
  if [[ ! -f "pubspec.yaml" ]]; then
    log_error "pubspec.yaml not found in template root. Check TEMPLATE_REPO."
    exit 1
  fi

  # Detect host OS for sed -i compatibility (macOS requires a backup suffix)
  if sed --version &>/dev/null 2>&1; then
    # GNU sed
    sed -i "s/^name:.*/name: ${project_name}/" pubspec.yaml
  else
    # BSD sed (macOS)
    sed -i '' "s/^name:.*/name: ${project_name}/" pubspec.yaml
  fi

  log_info "pubspec.yaml name → $project_name"

  # ── rename package (bundle ID + app name) ──
  if ! command -v rename &>/dev/null; then
    log_warn "'rename' Dart tool not found. Installing..."
    dart pub global activate rename
  fi

  rename setBundleId --value "$bundle_id"
  rename setAppName  --value "$app_name"

  log_success "Bundle ID → $bundle_id"
  log_success "App name  → $app_name"
}

# ------------------------------------------------------------------------------
# FLUTTER SETUP
# ------------------------------------------------------------------------------
flutter_setup() {
  log_step "Running flutter pub get"
  fvm flutter pub get
  log_success "Dependencies fetched."
}

# ------------------------------------------------------------------------------
# GIT INITIALISE & PUSH
# ------------------------------------------------------------------------------
init_and_push() {
  local repo_url="$1"
  local project_name="$2"

  log_step "Initialising Git and pushing to remote"

  git init
  git add .
  git commit -m "feat: initialise $project_name from Flutter MVVM template"
  git branch -M main
  git remote add origin "$repo_url"

  log_info "Pushing to $repo_url ..."
  if ! git push -u origin main; then
    log_error "Push failed. Ensure the remote repository exists, is empty, and you have write access."
    exit 1
  fi

  log_success "Pushed to $repo_url."
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}🚀 Flutter Project Installer${RESET}"
  printf '=%.0s' {1..50}; echo ""

  # ── Parse arguments ──
  if [[ $# -lt 5 ]]; then
    log_error "Not enough arguments supplied."
    usage
    exit 1
  fi

  local repo_url="$1"
  local project_name="$2"
  local app_name="$3"
  local bundle_id="$4"
  local fvm_version="$5"

  # ── Validate ──
  validate_inputs "$repo_url" "$project_name" "$app_name" "$bundle_id" "$fvm_version"

  # ── Work directory (set before clone so cleanup trap can find it) ──
  WORK_DIR="${SCRIPT_DIR}/temp_project_${project_name}"

  # ── Run steps ──
  check_dependencies
  setup_fvm "$fvm_version"
  clone_template "$WORK_DIR"

  pushd "$WORK_DIR" > /dev/null
    rename_project "$project_name" "$app_name" "$bundle_id"
    flutter_setup
    init_and_push "$repo_url" "$project_name"
  popd > /dev/null

  # Explicit cleanup (trap will also run but WORK_DIR cleared here first)
  rm -rf "$WORK_DIR"
  WORK_DIR=""

  # ── Summary ──
  echo ""
  printf '=%.0s' {1..50}; echo ""
  log_success "All done!"
  echo -e "  ${BOLD}Project:${RESET}   $project_name"
  echo -e "  ${BOLD}App name:${RESET}  $app_name"
  echo -e "  ${BOLD}Bundle ID:${RESET} $bundle_id"
  echo -e "  ${BOLD}Flutter:${RESET}   $fvm_version"
  echo -e "  ${BOLD}Remote:${RESET}    $repo_url"
  printf '=%.0s' {1..50}; echo ""
  echo ""
}

main "$@"