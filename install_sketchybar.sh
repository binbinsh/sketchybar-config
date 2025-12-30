echo "Installing Dependencies"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Packages
brew install lua

brew tap FelixKratz/formulae
brew install sketchybar

# Fonts
brew install --cask sf-symbols
brew install --cask font-sf-mono
brew install --cask font-sf-pro

curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v2.0.51/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf

# SbarLua
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua/ && make install && rm -rf /tmp/SbarLua/)

# Install config from GitHub
echo "Installing SketchyBar config from GitHub"
TARGET_DIR="$HOME/.config/sketchybar"
REPO_URL="https://github.com/binbinsh/sketchybar-config.git"

if ! command -v git >/dev/null 2>&1; then
  brew install git
fi

if [ -d "$TARGET_DIR/.git" ]; then
  current_remote=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || echo "")
  if [ "$current_remote" != "$REPO_URL" ]; then
    echo "Backing up existing non-matching repo at $TARGET_DIR"
    mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
  else
    echo "Updating existing repo in $TARGET_DIR"
    git -C "$TARGET_DIR" fetch --prune origin
    default_branch=$(git -C "$TARGET_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    if [ -z "$default_branch" ]; then
      if git -C "$TARGET_DIR" show-ref --verify --quiet refs/remotes/origin/main; then
        default_branch="main"
      elif git -C "$TARGET_DIR" show-ref --verify --quiet refs/remotes/origin/master; then
        default_branch="master"
      else
        default_branch=$(git -C "$TARGET_DIR" for-each-ref --format='%(refname:short)' refs/remotes/origin | sed -n 's|^origin/||p' | head -n 1)
      fi
    fi
    if [ -n "$default_branch" ]; then
      git -C "$TARGET_DIR" checkout "$default_branch" >/dev/null 2>&1 || true
      git -C "$TARGET_DIR" reset --hard "origin/$default_branch"
    else
      echo "Warning: Could not determine default branch for $TARGET_DIR; skipping reset."
    fi
  fi
elif [ -d "$TARGET_DIR" ]; then
  echo "Backing up existing non-git directory at $TARGET_DIR"
  mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
  git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
else
  git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
fi
brew services restart sketchybar

# For maximizing windows without yabai
brew install --cask hammerspoon

echo "Configuring Hammerspoon..."
mkdir -p "$HOME/.hammerspoon"
ln -sf "$SCRIPT_DIR/docs/hammerspoon_init.lua" "$HOME/.hammerspoon/init.lua"
