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
MAX_RETRIES="${APOD_RETRIES:-30}"    # tentativas aguardando internet
RETRY_DELAY="${APOD_RETRY_DELAY:-5}" # segundos entre tentativas
MAX_LOOKBACK="${APOD_LOOKBACK:-7}"   # dias pra trás quando a APOD de hoje é vídeo
# -----------------------------------------------------------------------------

mkdir -p "$DEST_DIR"
# stderr porque as funções abaixo são chamadas dentro de $(...) — um log em
# stdout viraria parte do valor de retorno. O journald captura os dois.
log() { echo "[apod] $*" >&2; }

# thumbs=true faz a API devolver thumbnail_url quando a APOD é um vídeo.
API_BASE="https://api.nasa.gov/planetary/apod?api_key=${API_KEY}&thumbs=true"

# Busca o JSON da APOD. $1: data YYYY-MM-DD (vazio = hoje).
fetch_apod() {
  local url="$API_BASE"
  [ -n "${1:-}" ] && url="${url}&date=$1"
  curl -fsS --max-time 20 "$url"
}

# Baixa a primeira URL candidata que seja de fato uma imagem. $1: JSON da APOD.
# Ecoa o caminho do arquivo baixado; retorna != 0 se nenhuma candidata servir.
download_image() {
  local json="$1" date_str candidates img_url ext candidate_out mime
  date_str="$(echo "$json" | jq -r '.date // ""')"

  # Ordem de preferência: alta resolução -> thumbnail (dias em que a APOD é
  # vídeo) -> url normal. Não dá pra decidir só pelo media_type: quando o vídeo
  # é um .mp4 hospedado na própria NASA (em vez de YouTube/Vimeo) a API devolve
  # thumbnail_url vazio e .url é o próprio vídeo. Também há dias em que o hdurl
  # está quebrado (404) e só a url normal funciona — por isso a cascata.
  candidates="$(echo "$json" | jq -r '[.hdurl, .thumbnail_url, .url] | map(select(. != null and . != "")) | .[]')"

  while IFS= read -r img_url; do
    [ -n "$img_url" ] || continue
    ext="${img_url##*.}"; ext="${ext%%\?*}"
    [ "${#ext}" -le 4 ] || ext="jpg"
    candidate_out="$DEST_DIR/apod-${date_str:-latest}.${ext}"

    if ! curl -fsSL --max-time 120 -o "$candidate_out" "$img_url"; then
      rm -f "$candidate_out"
      log "URL falhou ($img_url), tentando próxima..."
      continue
    fi

    # HTTP 200 não significa imagem: pode ser um vídeo ou uma página de erro.
    # Entregar isso pro gsettings deixa a área de trabalho no fundo liso padrão.
    mime="$(file --mime-type -b "$candidate_out")"
    case "$mime" in
      image/*) echo "$candidate_out"; return 0 ;;
    esac
    rm -f "$candidate_out"
    log "não é imagem ($mime): $img_url"
  done <<< "$candidates"

  return 1
}

# --- Aguarda a internet e busca o JSON da API --------------------------------
json=""
for i in $(seq 1 "$MAX_RETRIES"); do
  if json="$(fetch_apod)" && [ -n "$json" ]; then
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

# --- Pega a APOD de hoje; se não tiver imagem, volta um dia por vez ----------
out=""
for _ in $(seq 0 "$MAX_LOOKBACK"); do
  if out="$(download_image "$json")"; then
    break
  fi
  out=""

  day="$(echo "$json" | jq -r '.date // ""')"
  [ -n "$day" ] || break
  prev="$(date -u -d "$day - 1 day" +%F)"
  log "APOD de $day não tem imagem utilizável; tentando $prev..."

  if ! json="$(fetch_apod "$prev")" || [ -z "$json" ]; then
    log "não consegui buscar a APOD de $prev."
    json=""
    break
  fi
done

if [ -z "$out" ]; then
  log "falhou: nenhuma APOD com imagem nos últimos $MAX_LOOKBACK dias. Mantendo wallpaper atual."
  exit 1
fi

title="$(echo "$json" | jq -r '.title // "APOD"')"
date_str="$(echo "$json" | jq -r '.date // ""')"

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
