#!/usr/bin/env bash
#
# Debian 12 LXC bootstrap script
# Usage (as root on a fresh container):
#   bash setup.sh
#

set -euo pipefail

USERNAME="jcmarin"

# Paste your public key between the quotes (e.g. contents of ~/.ssh/id_ed25519.pub).
# Leave empty to skip SSH key setup.
SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCuEOAPfbRWtA+7mbwLzXLeoMK8449goPA8w7dtBd1CuINbrsZTKf/EjXUPsjOH1gXiDPFu3cmGwTCQahoHBkJuVrxTWisxXSq2d7sUU40ISHSm71Pp9zDQmoBE9fGpsqUNP8o4wnaewaT1WgeBqaLn0hZ9QJ89CmyYYAmGiAWHw4FDIs9n0n5PIXVC6bAcFGg/cQJ8tz/8nowzrh1QZw8riYIroW0vxig7/V9GPZSYtcnMwvkwJO0PxWi60Sv0YgyFGGEWPEorISW+UN75vvi8tVWyxwTNwYfKhDtY3hKS2gVfv3+Dx+S9jqLw0Wiz5JNzuOPhUsJoOpIfAkXqVYlbQpjUOChhxshgpBe/w6vPbFvIlYu9FcR3C8IXlki3GUCXCTPGs4SPpdRlwfYJ+IgSaYyctSBIUNphvK5PZXY8NVmJwpj5ndPY//LfdLx29T/1/yqOvIyGtKM6pc4gdFbHBjlmEBAjq8aqi+U+5yeAfEmQVWtzWSFwi43ibTRGM4U= jcmarin@Fractal"

# URL to a raw .zshrc file (e.g. https://raw.githubusercontent.com/<user>/dotfiles/main/zshrc).
# Leave empty to keep the default .zshrc that oh-my-zsh creates.
ZSHRC_URL="curl -fsSL https://raw.githubusercontent.com/jcmarinn/prefs/main/.zshrc"

# --- sanity check -----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: this script must be run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# --- system update ----------------------------------------------------------
echo ">>> Updating package lists..."
apt-get update -y

echo ">>> Upgrading installed packages..."
apt-get -o Dpkg::Options::="--force-confold" upgrade -y

# --- base packages ----------------------------------------------------------
# git is needed by the oh-my-zsh installer; ca-certificates for HTTPS curl
echo ">>> Installing base packages..."
apt-get install -y \
    sudo \
    curl \
    ca-certificates \
    git \
    zsh \
    python3.11 \
    python3.11-venv

# --- user creation ----------------------------------------------------------
if id "$USERNAME" &>/dev/null; then
  echo ">>> User '$USERNAME' already exists, skipping creation."
else
  echo ">>> Creating user '$USERNAME' (you will be prompted for a password)..."
  adduser --gecos "" "$USERNAME"
fi

# --- sudo access ------------------------------------------------------------
echo ">>> Adding '$USERNAME' to the sudo group..."
usermod -aG sudo "$USERNAME"

echo ">>> Adding dedicated sudoers entry for '$USERNAME'..."
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
echo "$USERNAME ALL=(ALL:ALL) ALL" > "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"  # syntax-check; bails out if invalid

# --- oh-my-zsh --------------------------------------------------------------
USER_HOME="/home/$USERNAME"
if [[ -d "$USER_HOME/.oh-my-zsh" ]]; then
  echo ">>> oh-my-zsh already installed for '$USERNAME', skipping."
else
  echo ">>> Installing oh-my-zsh for '$USERNAME'..."
  # Use `su -` (login shell) rather than `sudo -u` so jcmarin starts cleanly in
  # their own $HOME. With `sudo -u`, root's CWD (/root) leaks through and the
  # installer fails on its final `cd` back to the original directory.
  su - "$USERNAME" -c \
    'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
fi

# --- custom .zshrc ----------------------------------------------------------
if [[ -n "$ZSHRC_URL" ]]; then
  echo ">>> Downloading custom .zshrc for '$USERNAME'..."
  ZSHRC_PATH="$USER_HOME/.zshrc"

  # Back up oh-my-zsh's default once (only the first time, so re-runs don't clobber it).
  if [[ -f "$ZSHRC_PATH" && ! -f "$ZSHRC_PATH.bak" ]]; then
    cp "$ZSHRC_PATH" "$ZSHRC_PATH.bak"
    chown "$USERNAME:$USERNAME" "$ZSHRC_PATH.bak"
    echo "    backed up existing .zshrc to .zshrc.bak"
  fi

  curl -fsSL "$ZSHRC_URL" -o "$ZSHRC_PATH"
  chown "$USERNAME:$USERNAME" "$ZSHRC_PATH"
  chmod 644 "$ZSHRC_PATH"
  echo "    .zshrc installed from $ZSHRC_URL"
else
  echo ">>> No ZSHRC_URL set, keeping default .zshrc."
fi

# --- default shell ----------------------------------------------------------
echo ">>> Setting zsh as default shell for '$USERNAME'..."
chsh -s "$(command -v zsh)" "$USERNAME"

# --- ssh key ----------------------------------------------------------------
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  echo ">>> Installing SSH authorized key for '$USERNAME'..."
  SSH_DIR="$USER_HOME/.ssh"
  AUTH_KEYS="$SSH_DIR/authorized_keys"

  install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$SSH_DIR"
  touch "$AUTH_KEYS"
  chown "$USERNAME:$USERNAME" "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"

  # Append only if the key isn't already there (idempotent).
  if ! grep -qxF "$SSH_PUBLIC_KEY" "$AUTH_KEYS"; then
    echo "$SSH_PUBLIC_KEY" >> "$AUTH_KEYS"
    echo "    key added."
  else
    echo "    key already present, skipping."
  fi
else
  echo ">>> No SSH_PUBLIC_KEY set, skipping SSH key setup."
fi

# --- cleanup ----------------------------------------------------------------
echo ">>> Cleaning up apt cache..."
apt-get autoremove -y
apt-get clean

echo ""
echo "=========================================="
echo "  Setup complete."
echo "  Log in as '$USERNAME' to start using zsh + oh-my-zsh."
echo "  Python: $(python3.11 --version)"
echo "=========================================="
