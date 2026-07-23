# apod-wallpaper

Define automaticamente a **APOD** (Astronomy Picture of the Day, da NASA) como
wallpaper do seu desktop **GNOME** toda vez que você faz login.

![feito para](https://img.shields.io/badge/desktop-GNOME-blue) ![shell](https://img.shields.io/badge/shell-bash-green)

## Como funciona

- Um script Bash baixa a APOD do dia via [API da NASA](https://api.nasa.gov)
  e aplica no wallpaper (modos claro **e** escuro) usando `gsettings`.
- Um **serviço systemd de usuário** dispara o script no login da sessão gráfica
  (`graphical-session.target`) — momento em que o DBus da sessão já existe, que
  é o que o `gsettings` precisa (por isso não usa `@reboot` do cron).
- O script tem **retry** esperando a internet ficar pronta e, se falhar de vez,
  mantém o wallpaper atual em vez de deixar a tela preta.
- Dias em que a APOD é um vídeo → usa a thumbnail.
- Guarda só as últimas 10 imagens em `~/.local/share/apod-wallpaper/`.

## Requisitos

- Ubuntu / distro com **GNOME**
- `curl`, `jq`, `gsettings`, `systemd` (padrão no Ubuntu)

## Instalação

```bash
git clone https://github.com/isaac-prado/apod-wallpaper.git
cd apod-wallpaper
./install.sh
```

A partir do próximo login o wallpaper vira a APOD do dia.

## Uso

```bash
# Rodar manualmente agora
systemctl --user start apod-wallpaper.service

# Ver o log da última execução
journalctl --user -u apod-wallpaper.service --since today

# Desabilitar o disparo automático
systemctl --user disable apod-wallpaper.service
```

## Configuração (opcional)

Por padrão usa a `DEMO_KEY` da NASA (limite ~30 requisições/hora — suficiente
para o login). Para usar sua própria chave gratuita (https://api.nasa.gov),
edite `~/.config/systemd/user/apod-wallpaper.service` e descomente:

```ini
Environment=APOD_API_KEY=SUA_CHAVE_AQUI
```

Depois: `systemctl --user daemon-reload`.

Variáveis de ambiente suportadas pelo script:

| Variável | Padrão | Descrição |
|---|---|---|
| `APOD_API_KEY` | `DEMO_KEY` | Chave da API da NASA |
| `APOD_DIR` | `~/.local/share/apod-wallpaper` | Onde salvar as imagens |
| `APOD_RETRIES` | `30` | Tentativas aguardando internet |
| `APOD_RETRY_DELAY` | `5` | Segundos entre tentativas |

## Licença

MIT
