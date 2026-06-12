#!/usr/bin/env bash
#
# Debian 12 LXC bootstrap script
# Usage (as root on a fresh container):
#   bash setup.sh
#

set -euo pipefail

USERNAME="username"  # change this to your desired username

# Paste your public key between the quotes (e.g. contents of ~/.ssh/id_ed25519.pub).
# Leave empty to skip SSH key setup.
SSH_PUBLIC_KEY="" # paste your public key here

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

# --- tailscale --------------------------------------------------------------
# Installs and enables the Tailscale client so this LXC joins the tailnet.
#
# After the script finishes, authenticate the node by running:
#   sudo tailscale up
# Or, to skip the browser prompt, use an auth key:
#   sudo tailscale up --authkey=<key>   # from login.tailscale.com/admin/settings/keys
#
# For a service LXC that needs a public HTTPS endpoint (e.g. n8n), also run:
#   sudo tailscale funnel --bg --https=443 http://localhost:<port>
echo ">>> Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo ">>> Enabling and starting Tailscale service..."
systemctl enable --now tailscaled

echo ""
echo "  NOTE: Tailscale is installed but NOT yet authenticated."
echo "  Run the following to join the tailnet:"
echo "    sudo tailscale up"
echo "  Or with a pre-generated auth key:"
echo "    sudo tailscale up --authkey=<key>"

# --- cleanup ----------------------------------------------------------------
echo ">>> Cleaning up apt cache..."
apt-get autoremove -y
apt-get clean

echo ""
echo "=========================================="
echo "  Setup complete."
echo "  Log in as '$USERNAME' to start using zsh + oh-my-zsh."
echo "  Python: $(python3.11 --version)"
echo "  Tailscale: installed — run 'sudo tailscale up' to authenticate."
echo "=========================================="