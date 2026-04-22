#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# This script is meant to be run INSIDE the nvcr.io/nim/openfold/openfold2:2.4.0
# container, as root.
#
# It:
#   1. Ensures we're on Ubuntu 24.04 (noble)
#   2. Installs gpgv (required by apt for signature verification)
#   3. Installs apt itself (since the image doesn't ship with it)
#   4. Creates /etc/apt/sources.list pointing at Ubuntu 24.04 repos
#   5. Installs the ubuntu-keyring package (provides the archive signing keys,
#      including NO_PUBKEY 871920D1991BC93C)
#   6. Runs apt-get update and installs nginx
#
# Notes:
# - URLs include explicit versions; if Ubuntu updates them and you get 404s,
#   open the directory in a browser and pick the current *.deb.
# - This is an unsupported hack on top of a NIM runtime image; use for
#   experiments, not for production.
###############################################################################

echo "==> Checking that we are root..."
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root inside the container."
  echo "Start container with: docker run --rm -it -u 0:0 --entrypoint /bin/bash nvcr.io/nim/openfold/openfold2:2.4.0"
  exit 1
fi

echo "==> Checking Ubuntu codename (should be noble)..."
if ! grep -q "VERSION_CODENAME=noble" /etc/os-release 2>/dev/null; then
  echo "WARNING: VERSION_CODENAME is not 'noble'."
  echo "This script assumes Ubuntu 24.04 (noble); adjust URLs accordingly."
fi

cd /tmp

###############################################################################
# STEP 1: Install gpgv
# Why: apt uses gpgv to verify repository signatures; the NIM image doesn't
#      ship with it, so we add it manually via dpkg.
###############################################################################
echo "==> Installing gpgv (for apt signature verification)..."
GPGV_DEB_URL="http://security.ubuntu.com/ubuntu/pool/main/g/gnupg2/gpgv_2.4.4-2ubuntu17.4_amd64.deb"
# If this 404s in the future, browse:
#   http://security.ubuntu.com/ubuntu/pool/main/g/gnupg2/
# and pick the latest gpgv_*.deb for amd64.
wget -q "$GPGV_DEB_URL" -O gpgv.deb
dpkg -i gpgv.deb

###############################################################################
# STEP 2: Install apt
# Why: The NIM image has dpkg but no apt; we need the apt tools themselves.
###############################################################################
echo "==> Installing apt..."
APT_DEB_URL="http://mirrors.kernel.org/ubuntu/pool/main/a/apt/apt_2.7.14build2_amd64.deb"
# If this 404s in the future, browse:
#   http://mirrors.kernel.org/ubuntu/pool/main/a/apt/
# or a nearby Ubuntu mirror and pick apt_*.deb for noble/amd64.
wget -q "$APT_DEB_URL" -O apt.deb
dpkg -i apt.deb

###############################################################################
# STEP 3: Configure Ubuntu 24.04 (noble) repositories
# Why: Installing apt with dpkg does NOT create /etc/apt/sources.list.
#      We must tell apt which Ubuntu archives to use.
###############################################################################
echo "==> Writing /etc/apt/sources.list for Ubuntu noble..."
cat >/etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse restricted
deb http://security.ubuntu.com/ubuntu noble-security main universe multiverse restricted
EOF

###############################################################################
# STEP 4: Install ubuntu-keyring (archive signing keys)
# Why: apt-get update currently fails with NO_PUBKEY 871920D1991BC93C.
#      That key lives in the Ubuntu keyring for noble; since we can't use
#      apt yet, we fetch the keyring .deb and install it via dpkg.
###############################################################################
echo "==> Installing ubuntu-keyring (Ubuntu archive keys, incl. 871920D1991BC93C)..."
UBUNTU_KEYRING_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2023.11.28.1_all.deb"
# If this 404s in the future, browse:
#   http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/
# and pick ubuntu-keyring_*.deb (not ubuntu-cloud-keyring, etc.).
wget -q "$UBUNTU_KEYRING_DEB_URL" -O ubuntu-keyring.deb
dpkg -i ubuntu-keyring.deb

###############################################################################
# STEP 5: Update package lists
# Why: Now that apt, sources.list, and the keyring are in place, apt-get
#      can securely fetch and verify package lists.
###############################################################################
echo "==> Running apt-get update..."
apt-get update

###############################################################################
# STEP 6: Install nginx
# Why: With a normal Ubuntu apt setup in place, we can install packages
#      like nginx from the noble repositories.
###############################################################################
echo "==> Installing nginx..."
apt-get install -y nginx

echo "==> Done. nginx version:"
nginx -v || echo "nginx not found on PATH; installation may have failed."