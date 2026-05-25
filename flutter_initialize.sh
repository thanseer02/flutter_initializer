#!/usr/bin/env bash
# ==============================================================================
# Flutter Project Initializer — Interactive
# Run: bash install.sh
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

  if [[ ! "$repo_url" =~ ^(git@|https://).+ ]]; then
    log_error "Repo URL must start with 'git@' or 'https://'. Got: '$repo_url'"
    errors=$(( errors + 1 ))  # ✅ NOT ((errors++)) — that evaluates to 0 (falsy) and kills the script
  fi

  if [[ ! "$project_name" =~ ^[a-z][a-z0-9_]*$ ]]; then
    log_error "Project name must be lowercase snake_case with no leading digit. Got: '$project_name'"
    errors=$(( errors + 1 ))
  fi

  if [[ -z "$app_name" ]]; then
    log_error "App name cannot be empty."
    errors=$(( errors + 1 ))
  fi

  if [[ ! "$bundle_id" =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){1,}$ ]]; then
    log_error "Bundle ID must follow reverse-domain format (e.g. com.company.app). Got: '$bundle_id'"
    errors=$(( errors + 1 ))
  fi

  if [[ ! "$fvm_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    log_error "Flutter version must be semver (e.g. 3.19.0). Got: '$fvm_version'"
    errors=$(( errors + 1 ))
  fi

  return $errors
}

# ------------------------------------------------------------------------------
# PROMPT HELPERS
# Each loops until input passes its validation rule.
# Every `read` has `|| true` to prevent set -e from treating a terminal
# quirk / EOF as a fatal error.
# ------------------------------------------------------------------------------

prompt_project_name() {
  local varname="$1"
  local value=""
  while true; do
    read -rp "📦 Project Name (snake_case, e.g. my_app): " value || true
    if [[ "$value" =~ ^[a-z][a-z0-9_]*$ ]]; then
      break
    fi
    log_error "Must be lowercase letters, digits, and underscores only (no leading digit)."
  done
  printf -v "$varname" '%s' "$value"
}

prompt_app_name() {
  local varname="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -rp "📱 App Display Name (e.g. My App): " value || true
    if [[ -z "$value" ]]; then
      log_error "App name cannot be empty."
    fi
  done
  printf -v "$varname" '%s' "$value"
}

prompt_bundle_id() {
  local varname="$1"
  local value=""
  while true; do
    read -rp "🆔 Bundle ID (e.g. com.company.myapp): " value || true
    if [[ "$value" =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){1,}$ ]]; then
      break
    fi
    log_error "Must follow reverse-domain format, e.g. com.acme.myapp."
  done
  printf -v "$varname" '%s' "$value"
}

prompt_repo_url() {
  local varname="$1"
  local value=""
  while true; do
    read -rp "🔗 Git Repo URL (SSH or HTTPS): " value || true
    if [[ "$value" =~ ^(git@|https://).+ ]]; then
      break
    fi
    log_error "Must start with 'git@' (SSH) or 'https://' (HTTPS)."
  done
  printf -v "$varname" '%s' "$value"
}

prompt_fvm_version() {
  local varname="$1"
  local value=""
  while true; do
    read -rp "🧩 Flutter Version via FVM (e.g. 3.19.0): " value || true
    if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
      break
    fi
    log_error "Must be a valid semver version, e.g. 3.19.0 or 3.19.0-beta."
  done
  printf -v "$varname" '%s' "$value"
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
  require_cmd git  "https://git-scm.com/downloads"
  require_cmd dart "Install Flutter SDK: https://docs.flutter.dev/get-started/install"
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

  local pub_cache_bin
  pub_cache_bin="$(dart pub cache path 2>/dev/null || echo "$HOME/.pub-cache")/bin"
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

  if [[ ! -f "pubspec.yaml" ]]; then
    log_error "pubspec.yaml not found in template root. Check TEMPLATE_REPO."
    exit 1
  fi

  if sed --version &>/dev/null 2>&1; then
    sed -i "s/^name:.*/name: ${project_name}/" pubspec.yaml        # GNU sed
  else
    sed -i '' "s/^name:.*/name: ${project_name}/" pubspec.yaml     # BSD sed (macOS)
  fi
  log_info "pubspec.yaml name → $project_name"

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
    log_error "Push failed. Ensure the remote repo exists, is empty, and you have write access."
    exit 1
  fi

  log_success "Pushed to $repo_url."
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
  clear
  echo ""
  echo -e "${BOLD}🚀 Flutter Project Initializer${RESET}"
  printf '=%.0s' {1..50}; echo ""

  echo ""
  echo -e "${CYAN}Please fill in your project details:${RESET}"
  echo ""

  local project_name="" app_name="" bundle_id="" repo_url="" fvm_version="" confirm=""

  prompt_project_name project_name
  prompt_app_name     app_name
  prompt_bundle_id    bundle_id
  prompt_repo_url     repo_url
  prompt_fvm_version  fvm_version

  # ── CONFIRMATION ──
  echo ""
  echo -e "${YELLOW}Please confirm your details:${RESET}"
  printf '%.0s─' {1..40}; echo ""
  echo -e "  ${BOLD}Project Name :${RESET} $project_name"
  echo -e "  ${BOLD}App Name     :${RESET} $app_name"
  echo -e "  ${BOLD}Bundle ID    :${RESET} $bundle_id"
  echo -e "  ${BOLD}Repo URL     :${RESET} $repo_url"
  echo -e "  ${BOLD}Flutter Ver  :${RESET} $fvm_version"
  printf '%.0s─' {1..40}; echo ""
  echo ""
  read -rp "▶ Continue? (y/n): " confirm || true
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_warn "Cancelled by user."
    exit 0
  fi

  # ── SET WORK DIR (before clone so EXIT trap can clean it up) ──
  WORK_DIR="${SCRIPT_DIR}/temp_project_${project_name}"

  # ── EXECUTION FLOW ──
  check_dependencies
  setup_fvm "$fvm_version"
  clone_template "$WORK_DIR"

  pushd "$WORK_DIR" > /dev/null
    rename_project "$project_name" "$app_name" "$bundle_id"
    flutter_setup
    init_and_push "$repo_url" "$project_name"
  popd > /dev/null

  rm -rf "$WORK_DIR"
  WORK_DIR=""

  # ── SUCCESS SUMMARY ──
  echo ""
  printf '=%.0s' {1..50}; echo ""
  log_success "🎉 Project Created Successfully!"
  echo ""
  echo -e "  📁 ${BOLD}Repo:${RESET} ${CYAN}$repo_url${RESET}"
  echo ""
  echo -e "  ${BOLD}👉 Next steps:${RESET}"
  echo "     git clone $repo_url"
  echo "     cd $project_name"
  echo "     fvm flutter run"
  echo ""
  printf '=%.0s' {1..50}; echo ""
  echo ""
}

main "$@"