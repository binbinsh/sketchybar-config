#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="${HOME}/.config/sketchybar"
REPO_URL="https://github.com/binbinsh/sketchybar-config.git"
SKETCHYBAR_APP_FONT_URL="https://github.com/kvndrsslr/sketchybar-app-font/releases/latest/download/sketchybar-app-font.ttf"

info() { printf "[i] %s\n" "$*"; }
warn() { printf "[!] %s\n" "$*"; }
done_msg() { printf "[+] %s\n" "$*"; }
die() { printf "[x] %s\n" "$*" >&2; exit 1; }

ensure_brew() {
  command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install Homebrew first, then rerun this script."
}

ensure_formula() {
  local formula="$1"
  brew list --formula "$formula" >/dev/null 2>&1 && return
  info "Installing brew formula: $formula"
  brew install "$formula"
}

ensure_cask() {
  local cask="$1"
  brew list --cask "$cask" >/dev/null 2>&1 && return
  info "Installing brew cask: $cask"
  brew install --cask "$cask"
}

download_file() {
  local url="$1"
  local dest="$2"
  local tmp

  tmp="$(mktemp "${dest}.XXXXXX")"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 -o "$tmp" "$url"
  mv "$tmp" "$dest"
}

has_sarasa_term_sc_font() {
  mdfind 'kMDItemFonts == "Sarasa Term SC"' | grep -q . && return 0
  find "${HOME}/Library/Fonts" /Library/Fonts -maxdepth 1 \
    \( -name 'SarasaTermSC-*.ttf' -o -name 'Sarasa-SuperTTC.ttc' \) 2>/dev/null | grep -q .
}

install_fonts() {
  local cask
  for cask in sf-symbols font-sf-mono font-sf-pro; do
    ensure_cask "$cask"
  done

  if ! has_sarasa_term_sc_font; then
    info "Installing Sarasa Gothic bundle for Sarasa Term SC"
    ensure_cask font-sarasa-gothic
    has_sarasa_term_sc_font || warn "font-sarasa-gothic installed, but Sarasa Term SC was not detected yet"
  fi

  mkdir -p "${HOME}/Library/Fonts"
  info "Installing latest sketchybar-app-font"
  download_file "$SKETCHYBAR_APP_FONT_URL" "${HOME}/Library/Fonts/sketchybar-app-font.ttf"
}

install_sbarlua() {
  local build_dir

  build_dir="$(mktemp -d)"
  git clone --depth=1 https://github.com/FelixKratz/SbarLua.git "${build_dir}/SbarLua"
  make -C "${build_dir}/SbarLua" install
  rm -rf "$build_dir"
}

backup_target() {
  local backup_dir="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
  warn "Backing up existing target to $backup_dir"
  mv "$TARGET_DIR" "$backup_dir"
}

clone_repo() {
  info "Cloning SketchyBar config into $TARGET_DIR"
  git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
}

default_branch() {
  git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'
}

sync_repo() {
  local branch
  local remote_url

  if [ ! -e "$TARGET_DIR" ]; then
    clone_repo
    return
  fi

  if [ ! -d "${TARGET_DIR}/.git" ]; then
    backup_target
    clone_repo
    return
  fi

  remote_url="$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)"
  if [ "$remote_url" != "$REPO_URL" ] || [ -n "$(git -C "$TARGET_DIR" status --porcelain --untracked-files=all)" ]; then
    backup_target
    clone_repo
    return
  fi

  info "Updating existing repo in $TARGET_DIR"
  git -C "$TARGET_DIR" fetch --prune origin
  branch="$(default_branch "$TARGET_DIR")"
  [ -n "$branch" ] || branch="main"
  git -C "$TARGET_DIR" switch "$branch" >/dev/null 2>&1 || git -C "$TARGET_DIR" checkout "$branch" >/dev/null 2>&1 || true

  if git -C "$TARGET_DIR" merge --ff-only "origin/$branch" >/dev/null 2>&1; then
    done_msg "Updated $TARGET_DIR to origin/$branch"
  else
    warn "Fast-forward update failed for $TARGET_DIR"
    backup_target
    clone_repo
  fi
}

print_rectangle_notice() {
  info "Window management is not installed by this script"
  info "Use your Rectangle build separately: https://github.com/binbinsh/rectangle"
  info "Recommended Rectangle settings are documented in ${TARGET_DIR}/docs/rectangle.md"
}

main() {
  local formula

  ensure_brew

  info "Installing dependencies"
  for formula in git lua; do
    ensure_formula "$formula"
  done

  brew tap FelixKratz/formulae >/dev/null
  ensure_formula sketchybar
  install_fonts
  install_sbarlua
  sync_repo

  brew services restart sketchybar
  print_rectangle_notice
  done_msg "SketchyBar installation completed"
}

main "$@"
