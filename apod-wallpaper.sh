#!/usr/bin/env bash
#
# apod-wallpaper.sh — Baixa a Astronomy Picture of the Day (NASA) e a define
# como wallpaper do GNOME (modo claro e escuro).
#
# Uso:   apod-wallpaper.sh
# Config: variáveis de ambiente opcionais abaixo.

set -euo pipefail

# ---- Configuração -----------------------------------------------------------
# Pegue uma chave gratuita em https://api.nasa.gov (DEMO_KEY funciona, mas tem
# limite baixo: ~30 req/hora). Defina APOD_API_KEY no service pra usar a sua.
API_KEY="${APOD_API_KEY:-DEMO_KEY}"
DEST_DIR="${APOD_DIR:-$HOME/.local/share/apod-wallpaper}"
MAX_RETRIES="${APOD_RETRIES:-30}"   # tentativas aguardando internet
RETRY_DELAY="${APOD_RETRY_DELAY:-5}" # segundos entre tentativas
# -----------------------------------------------------------------------------

mkdir -p "$DEST_DIR"
log() { echo "[apod] $*"; }

# thumbs=true faz a API devolver thumbnail_url quando a APOD é um vídeo.
API_URL="https://api.nasa.gov/planetary/apod?api_key=${API_KEY}&thumbs=true"

# --- Aguarda a internet e busca o JSON da API --------------------------------
json=""
for i in $(seq 1 "$MAX_RETRIES"); do
  if json="$(curl -fsS --max-time 20 "$API_URL")" && [ -n "$json" ]; then
    break
  fi
  log "sem resposta da API (tentativa $i/$MAX_RETRIES), aguardando ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
  json=""
done

if [ -z "$json" ]; then
  log "falhou: não consegui contatar a API da NASA. Mantendo wallpaper atual."
  exit 1
fi

# --- Monta a lista de URLs candidatas (em ordem de preferência) --------------
# Algumas vezes a APOD tem hdurl quebrado (404) mas a url normal funciona — por
# isso tentamos várias em cascata em vez de confiar numa só.
media_type="$(echo "$json" | jq -r '.media_type // "image"')"
title="$(echo "$json" | jq -r '.title // "APOD"')"

if [ "$media_type" = "image" ]; then
  candidates="$(echo "$json" | jq -r '[.hdurl, .url] | map(select(. != null and . != "")) | .[]')"
else
  # vídeo (ou outro): usa a thumbnail, depois a url como último recurso
  candidates="$(echo "$json" | jq -r '[.thumbnail_url, .url] | map(select(. != null and . != "")) | .[]')"
fi

if [ -z "$candidates" ]; then
  log "falhou: JSON sem URL de imagem utilizável. Mantendo wallpaper atual."
  exit 1
fi

# --- Baixa a imagem (tenta cada candidata até uma funcionar) -----------------
date_str="$(echo "$json" | jq -r '.date // ""')"
out=""
while IFS= read -r img_url; do
  [ -n "$img_url" ] || continue
  ext="${img_url##*.}"; ext="${ext%%\?*}"
  [ "${#ext}" -le 4 ] || ext="jpg"
  candidate_out="$DEST_DIR/apod-${date_str:-latest}.${ext}"
  if curl -fsSL --max-time 120 -o "$candidate_out" "$img_url"; then
    out="$candidate_out"
    log "imagem baixada de: $img_url"
    break
  fi
  log "URL falhou ($img_url), tentando próxima..."
done <<< "$candidates"

if [ -z "$out" ]; then
  log "falhou: nenhuma URL de imagem funcionou. Mantendo wallpaper atual."
  exit 1
fi

# Salva metadados (título/data/explicação) para referência.
echo "$json" | jq -r '{date, title, explanation, media_type, hdurl, url} ' \
  > "$DEST_DIR/last.json" 2>/dev/null || true

# --- Define o wallpaper (GNOME: claro + escuro) ------------------------------
uri="file://$out"
gsettings set org.gnome.desktop.background picture-uri "$uri"
gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
gsettings set org.gnome.desktop.background picture-options 'zoom'

log "wallpaper atualizado: \"$title\" (${date_str:-?}) -> $out"

# --- Limpeza: mantém apenas as últimas 10 imagens ----------------------------
ls -1t "$DEST_DIR"/apod-*.* 2>/dev/null | tail -n +11 | xargs -r rm -f || true
