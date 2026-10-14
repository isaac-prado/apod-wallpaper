#!/usr/bin/env bash
#
# apod-wallpaper.sh — Baixa a Astronomy Picture of the Day (NASA) e a define
# como wallpaper do GNOME (modo claro e escuro).
#
# Uso:   apod-wallpaper.sh
# Config: variáveis de ambiente opcionais abaixo.

set -euo pipefail

# ---- Configuração -----------------------------------------------------------
DEST_DIR="${APOD_DIR:-$HOME/.local/share/apod-wallpaper}"
MAX_RETRIES="${APOD_RETRIES:-30}"    # tentativas aguardando internet
RETRY_DELAY="${APOD_RETRY_DELAY:-5}" # segundos entre tentativas
MAX_LOOKBACK="${APOD_LOOKBACK:-7}"   # dias pra trás quando a APOD de hoje é vídeo
MIN_WIDTH="${APOD_MIN_WIDTH:-800}"   # abaixo disso não é foto
# -----------------------------------------------------------------------------

mkdir -p "$DEST_DIR"
# stderr porque as funções abaixo são chamadas dentro de $(...) — um log em
# stdout viraria parte do valor de retorno. O journald captura os dois.
log() { echo "[apod] $*" >&2; }

FEED_URL="https://science.nasa.gov/feed/apod-basic/"

# A API api.nasa.gov/planetary/apod devolve o logo da NASA no lugar da imagem
# desde a migração do site (nasa/apod-api#184), então usamos o feed RSS oficial.

# Lista "data|título|hdurl" de cada item do feed que tem imagem, do mais novo
# pro mais antigo. Dias de vídeo vêm sem hdurl e são ignorados.
parse_feed() {
  awk '
    /<item>/            { title = ""; date = ""; hd = "" }
    /<title>/ && title == "" { title = $0; sub(/.*<title>/, "", title); sub(/<\/title>.*/, "", title) }
    /<pubDate>/         { date = $0; sub(/.*<pubDate>/, "", date); sub(/<\/pubDate>.*/, "", date) }
    /<apod:hdurl>/      { hd = $0; sub(/.*<apod:hdurl>/, "", hd); sub(/<\/apod:hdurl>.*/, "", hd) }
    /<\/item>/          { if (hd != "") print date "|" title "|" hd }
  ' | while IFS='|' read -r date title hd; do
    printf '%s|%s|%s\n' "$(date -u -d "$date" +%F)" "$title" "${hd//&#038;/\&}"
  done
}

# Baixa a primeira URL candidata que seja de fato uma imagem grande. $1: data, $2: hdurl.
# Ecoa o caminho do arquivo baixado; retorna != 0 se nenhuma candidata servir.
download_image() {
  local date_str="$1" hdurl="$2" original img_url ext candidate_out mime width
  # O hdurl passa por um redimensionador; o original em resolução total fica em
  # /content/dam/ e vem sem query string.
  original="${hdurl%%\?*}"
  original="${original/\/dynamicimage\/assets\/science\//\/content\/dam\/science\/}"

  for img_url in "$original" "$hdurl"; do
    ext="${img_url%%\?*}"; ext="${ext##*.}"
    [ "${#ext}" -le 4 ] || ext="jpg"
    candidate_out="$DEST_DIR/apod-${date_str}.${ext}"

    if ! curl -fsSL --max-time 120 -o "$candidate_out" "$img_url"; then
      rm -f "$candidate_out"
      log "URL falhou ($img_url), tentando próxima..."
      continue
    fi

    # HTTP 200 não significa imagem: pode ser uma página de erro. Entregar isso
    # pro gsettings deixa a área de trabalho no fundo liso padrão.
    mime="$(file --mime-type -b "$candidate_out")"
    # Em `file`, a densidade do JPEG (100x100) vem antes das dimensões: vale o último NxM.
    width="$(file -b "$candidate_out" | grep -oE '[0-9]+ ?x ?[0-9]+' | tail -1 | sed 's/ \?x.*//')"
    if [[ "$mime" == image/* ]] && [ "${width:-0}" -ge "$MIN_WIDTH" ]; then
      echo "$candidate_out"; return 0
    fi
    rm -f "$candidate_out"
    log "descartado ($mime, ${width:-?}px, mín. ${MIN_WIDTH}px): $img_url"
  done

  return 1
}

# --- Aguarda a internet e baixa o feed ---------------------------------------
entries=""
for i in $(seq 1 "$MAX_RETRIES"); do
  if feed="$(curl -fsS --max-time 20 "$FEED_URL")" && entries="$(parse_feed <<< "$feed")" && [ -n "$entries" ]; then
    break
  fi
  entries=""
  log "sem resposta do feed (tentativa $i/$MAX_RETRIES), aguardando ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
done

if [ -z "$entries" ]; then
  log "falhou: não consegui ler o feed da NASA. Mantendo wallpaper atual."
  exit 1
fi

# --- Pega a APOD mais recente que tenha imagem utilizável --------------------
out=""; count=0
while IFS='|' read -r date_str title hdurl; do
  [ "$count" -le "$MAX_LOOKBACK" ] || break
  count=$((count + 1))
  if out="$(download_image "$date_str" "$hdurl")"; then
    break
  fi
  out=""
  log "APOD de $date_str não tem imagem utilizável; tentando a anterior..."
done <<< "$entries"

if [ -z "$out" ]; then
  log "falhou: nenhuma APOD com imagem nos últimos $MAX_LOOKBACK dias. Mantendo wallpaper atual."
  exit 1
fi

# Salva metadados para referência.
jq -n --arg date "$date_str" --arg title "$title" --arg hdurl "$hdurl" \
  '{date: $date, title: $title, hdurl: $hdurl}' > "$DEST_DIR/last.json" 2>/dev/null || true

# --- Define o wallpaper (GNOME: claro + escuro) ------------------------------
uri="file://$out"
gsettings set org.gnome.desktop.background picture-uri "$uri"
gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
gsettings set org.gnome.desktop.background picture-options 'zoom'

log "wallpaper atualizado: \"$title\" (${date_str:-?}) -> $out"

# --- Limpeza: mantém apenas as últimas 10 imagens ----------------------------
ls -1t "$DEST_DIR"/apod-*.* 2>/dev/null | tail -n +11 | xargs -r rm -f || true
