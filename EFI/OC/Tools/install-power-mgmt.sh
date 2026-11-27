#!/bin/bash
# Install power management optimizations for Moto Book 60 (240H)
# Run with sudo after macOS is installed

set -euo pipefail

echo "Installing power management optimizations..."

# 1. Install timer-coalesce script and LaunchDaemon
echo "Installing timer coalescing..."
cp timer-coalesce.sh /usr/local/sbin/timer-coalesce.sh
chmod 755 /usr/local/sbin/timer-coalesce.sh
cp local.timer-coalesce.plist /Library/LaunchDaemons/local.timer-coalesce.plist
launchctl load -w /Library/LaunchDaemons/local.timer-coalesce.plist

# 2. Disable mediaanalysisd and photoanalysisd (background GPU work)
echo "Disabling background photo analysis..."
launchctl disable gui/$(id -u)/com.apple.photoanalysisd 2>/dev/null || true
launchctl disable gui/$(id -u)/com.apple.mediaanalysisd 2>/dev/null || true

# 3. Set reduce transparency and motion for smoother animations
defaults write com.apple.universalaccess ReduceTransparency -bool true
defaults write com.apple.universalaccess ReduceMotion -bool true

# 4. Disable proximity wake
pmset -a proximitywake 0

# 5. Set hibernatemode to 3 (safe sleep)
pmset -a hibernatemode 3

# 6. Disable sleep (lid close = display off only)
pmset -a sleep 0
pmset -a displaysleep 10
pmset -a disksleep 10
pmset -a powernap 0
pmset -a standby 0
pmset -a autopoweroff 0

echo "Power management optimizations installed."
echo "Reboot required for all changes to take effect."
