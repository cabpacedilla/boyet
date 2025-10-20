#!/bin/bash

set -e  # Exit on any error

echo "🧹 Starting complete ydotool removal process..."

# Stop and disable systemd services
echo "🛑 Stopping ydotool systemd services..."
sudo systemctl stop ydotoold 2>/dev/null || true
sudo systemctl disable ydotoold 2>/dev/null || true

# Stop and disable user services
systemctl --user stop ydotoold 2>/dev/null || true
systemctl --user disable ydotoold 2>/dev/null || true

# Kill any running ydotoold processes
echo "🔫 Killing any running ydotoold processes..."
sudo pkill -f ydotoold 2>/dev/null || true
sleep 2  # Wait a moment for processes to terminate

# Force kill if any remain
sudo pkill -9 -f ydotoold 2>/dev/null || true

# Remove via package manager
echo "📦 Removing ydotool package..."
sudo dnf remove -y ydotool 2>/dev/null || echo "Package not installed via dnf"

# Remove systemd service files
echo "🗑️ Removing systemd service files..."
sudo rm -f /usr/lib/systemd/system/ydotoold.service
sudo rm -f /etc/systemd/system/ydotoold.service
sudo rm -f /usr/local/lib/systemd/system/ydotoold.service

# Remove user systemd service files
rm -f ~/.config/systemd/user/ydotoold.service
rm -f ~/.local/share/systemd/user/ydotoold.service

# Reload systemd
echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true

# Remove binary files
echo "🔧 Removing binary files..."
sudo rm -f /usr/local/bin/ydotool
sudo rm -f /usr/local/bin/ydotoold
sudo rm -f /usr/bin/ydotool
sudo rm -f /usr/bin/ydotoold
sudo rm -f /bin/ydotool
sudo rm -f /bin/ydotoold

# Remove configuration and data files
echo "📁 Removing configuration and data files..."
rm -rf ~/.config/ydotool
rm -rf ~/.local/share/ydotool
rm -rf ~/.ydotool
sudo rm -rf /etc/ydotool
sudo rm -rf /usr/local/etc/ydotool

# Remove socket files
echo "🔌 Removing socket files..."
rm -f ~/.ydotool_socket
rm -f /tmp/.ydotool_socket*
sudo rm -f /tmp/.ydotool_socket*

# Remove source build directory if exists
echo "🏗️ Checking for source build directory..."
if [ -d "$HOME/ydotool" ]; then
    echo "Found ~/ydotool directory - removing..."
    rm -rf "$HOME/ydotool"
fi

# Remove from PATH in shell config files (optional)
echo "🔄 Cleaning shell configuration files..."
sed -i '/YDOTOOL_SOCKET/d' ~/.bashrc 2>/dev/null || true
sed -i '/YDOTOOL_SOCKET/d' ~/.profile 2>/dev/null || true
sed -i '/YDOTOOL_SOCKET/d' ~/.zshrc 2>/dev/null || true

# Final verification
echo "✅ Verification:"
echo "Checking for remaining ydotool processes..."
pgrep -f ydotool && echo "WARNING: Some ydotool processes still running!" || echo "No ydotool processes found"

echo "Checking for ydotool binary..."
which ydotool && echo "WARNING: ydotool binary still exists!" || echo "ydotool binary not found"

echo ""
echo "🎉 ydotool removal completed successfully!"
echo "You may want to:"
echo "1. Restart your terminal session"
echo "2. Run 'source ~/.bashrc' to update your environment"
