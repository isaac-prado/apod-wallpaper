#!/usr/bin/env bash
#
# install.sh — Instala o apod-wallpaper para o usuário atual (GNOME/systemd).
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"

echo "==> Instalando script em $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 0755 "$SRC_DIR/apod-wallpaper.sh" "$BIN_DIR/apod-wallpaper.sh"

echo "==> Instalando unit systemd em $UNIT_DIR"
mkdir -p "$UNIT_DIR"
install -m 0644 "$SRC_DIR/systemd/apod-wallpaper.service" "$UNIT_DIR/apod-wallpaper.service"

echo "==> Habilitando disparo no login"
systemctl --user daemon-reload
systemctl --user enable apod-wallpaper.service

echo "==> Rodando uma vez agora"
"$BIN_DIR/apod-wallpaper.sh" || true

echo
echo "Pronto! A partir do próximo login o wallpaper será a APOD do dia."
echo "Para rodar manualmente:  systemctl --user start apod-wallpaper.service"
echo "Para ver o log:          journalctl --user -u apod-wallpaper.service --since today"
