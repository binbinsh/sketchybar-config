#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="$HOME/.config/sketchybar"
REPO_URL="https://github.com/binbinsh/sketchybar-config.git"
SKETCHYBAR_APP_FONT_URL="https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v2.0.51/sketchybar-app-font.ttf"

log() { printf "[+] %s\n" "$*"; }
info() { printf "[i] %s\n" "$*"; }
warn() { printf "[!] %s\n" "$*"; }
err() { printf "[x] %s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

install_formula() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    info "brew formula already installed: $formula"
  else
    info "Installing brew formula: $formula"
    brew install "$formula"
  fi
}

install_cask() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    info "brew cask already installed: $cask"
  else
    info "Installing brew cask: $cask"
    brew install --cask "$cask"
  fi
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
  find "$HOME/Library/Fonts" /Library/Fonts -maxdepth 1 \
    \( -name 'SarasaTermSC-*.ttf' -o -name 'Sarasa-SuperTTC.ttc' \) 2>/dev/null | grep -q .
}

has_sketchybar_app_font() {
  mdfind 'kMDItemFSName == "sketchybar-app-font.ttf"' | grep -q . && return 0
  [ -f "$HOME/Library/Fonts/sketchybar-app-font.ttf" ]
}

ensure_font_dir() {
  mkdir -p "$HOME/Library/Fonts"
}

install_fonts() {
  install_cask sf-symbols
  install_cask font-sf-mono
  install_cask font-sf-pro

  if has_sarasa_term_sc_font; then
    info "Sarasa Term SC already available"
  else
    info "Installing Sarasa Gothic bundle for Sarasa Term SC"
    install_cask font-sarasa-gothic
    if has_sarasa_term_sc_font; then
      log "Sarasa Term SC font is available"
    else
      warn "font-sarasa-gothic installed, but Sarasa Term SC was not detected yet"
      warn "macOS font registration may complete after restarting affected apps"
    fi
  fi

  ensure_font_dir
  if has_sketchybar_app_font; then
    info "sketchybar-app-font already installed"
  else
    info "Installing sketchybar-app-font"
    download_file "$SKETCHYBAR_APP_FONT_URL" "$HOME/Library/Fonts/sketchybar-app-font.ttf"
  fi
}

install_sbarlua() {
  local build_dir

  build_dir="$(mktemp -d)"
  git clone --depth=1 https://github.com/FelixKratz/SbarLua.git "$build_dir/SbarLua"
  (
    cd "$build_dir/SbarLua"
    make install
  )
  rm -rf "$build_dir"
}

detect_default_branch() {
  local repo_dir="$1"
  local branch=""

  branch="$(git -C "$repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  if [ -n "$branch" ]; then
    printf "%s\n" "$branch"
    return 0
  fi

  if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/main; then
    printf "main\n"
    return 0
  fi

  if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/master; then
    printf "master\n"
    return 0
  fi

  git -C "$repo_dir" for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | sed -n 's|^origin/||p' | head -n 1
}

backup_existing_target() {
  local backup_dir="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
  warn "Backing up existing target to $backup_dir"
  mv "$TARGET_DIR" "$backup_dir"
}

clone_repo() {
  info "Cloning SketchyBar config into $TARGET_DIR"
  git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
}

sync_repo() {
  if [ -d "$TARGET_DIR/.git" ]; then
    local current_remote
    local default_branch

    current_remote="$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || printf "")"
    if [ "$current_remote" != "$REPO_URL" ]; then
      backup_existing_target
      clone_repo
      return 0
    fi

    if [ -n "$(git -C "$TARGET_DIR" status --porcelain --untracked-files=all)" ]; then
      warn "Local changes detected in $TARGET_DIR"
      backup_existing_target
      clone_repo
      return 0
    fi

    info "Updating existing repo in $TARGET_DIR"
    git -C "$TARGET_DIR" fetch --prune origin
    default_branch="$(detect_default_branch "$TARGET_DIR")"

    if [ -z "$default_branch" ]; then
      warn "Could not determine default branch for $TARGET_DIR; leaving repo untouched"
      return 0
    fi

    git -C "$TARGET_DIR" checkout "$default_branch" >/dev/null 2>&1 || true
    if git -C "$TARGET_DIR" merge --ff-only "origin/$default_branch" >/dev/null 2>&1; then
      log "Updated $TARGET_DIR to origin/$default_branch"
    else
      warn "Fast-forward update failed for $TARGET_DIR"
      backup_existing_target
      clone_repo
    fi
    return 0
  fi

  if [ -d "$TARGET_DIR" ]; then
    backup_existing_target
  fi

  clone_repo
}

configure_hammerspoon() {
  install_cask hammerspoon
  info "Configuring Hammerspoon"
  mkdir -p "$HOME/.hammerspoon"
  ln -sf "$TARGET_DIR/docs/hammerspoon_init.lua" "$HOME/.hammerspoon/init.lua"
}

main() {
  if ! have brew; then
    err "Homebrew is required. Install Homebrew first, then rerun this script."
    exit 1
  fi

  info "Installing dependencies"
  install_formula git
  install_formula lua
  install_formula libimobiledevice

  brew tap FelixKratz/formulae
  install_formula sketchybar

  install_fonts
  install_sbarlua
  sync_repo

  brew services restart sketchybar
  configure_hammerspoon

  log "SketchyBar installation completed"
}

main "$@"
