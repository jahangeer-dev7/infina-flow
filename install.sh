#!/usr/bin/env bash
set -euo pipefail

# InfinaFlow - One-Click Installer for Omarchy Linux / Hyprland
echo "=========================================================="
echo "  InfinaFlow: Linux Native Hands-Free Voice Assistant"
echo "  Optimized for Omarchy Linux (Hyprland + Quickshell)"
echo "=========================================================="

INSTALL_DIR="${HOME}/.local/share/infina-flow"
BIN_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
VENV_DIR="${HOME}/.local/share/vox-handsfree-venv"

echo "[1/5] Checking system dependencies..."
MISSING_DEPS=()
for cmd in hyprctl wtype wpctl qs python3 grim; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "Warning: The following optional/recommended tools were not found: ${MISSING_DEPS[*]}"
    echo "Install them using: sudo pacman -S ${MISSING_DEPS[*]}"
fi

echo "[2/5] Setting up Python virtual environment..."
mkdir -p "${VENV_DIR}"
if [ ! -f "${VENV_DIR}/bin/python" ]; then
    python3 -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet
"${VENV_DIR}/bin/pip" install openwakeword sounddevice numpy onnxruntime --quiet

echo "[3/5] Installing binaries and Quickshell HUD..."
mkdir -p "${BIN_DIR}" "${INSTALL_DIR}/hud" "${SYSTEMD_DIR}"
cp bin/infina-flow "${BIN_DIR}/infina-flow"
chmod +x "${BIN_DIR}/infina-flow"
cp hud/shell.qml "${INSTALL_DIR}/hud/shell.qml"
cp systemd/infina-flow.service "${SYSTEMD_DIR}/infina-flow.service"

echo "[4/5] Checking API Configuration..."
CONFIG_DIR="${HOME}/.config/infina-flow"
mkdir -p "${CONFIG_DIR}"
if [ ! -f "${CONFIG_DIR}/infina.env" ] && [ ! -f "${HOME}/.config/voxtype/voxtype.env" ]; then
    cp config.example.env "${CONFIG_DIR}/infina.env"
    echo "Created template configuration at ${CONFIG_DIR}/infina.env."
    echo "Please add your GROQ_API_KEY (and optional NVIDIA_API_KEY)."
fi

echo "[5/5] Reloading and enabling systemd user service..."
systemctl --user daemon-reload
systemctl --user enable infina-flow.service
systemctl --user restart infina-flow.service

echo "=========================================================="
echo "  InfinaFlow installed and running successfully!"
echo "  - Wake Word: Say 'Hey Jarvis'"
echo "  - Logs: journalctl --user -u infina-flow.service -f"
echo "=========================================================="
