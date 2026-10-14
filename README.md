# apod-wallpaper

Automatically sets the **APOD** (NASA's Astronomy Picture of the Day) as your
**GNOME** desktop wallpaper every time you log in.

![desktop](https://img.shields.io/badge/desktop-GNOME-blue) ![shell](https://img.shields.io/badge/shell-bash-green)

## How it works

- A Bash script downloads the day's APOD from NASA's [official APOD RSS feed](https://science.nasa.gov/feed/apod-basic/)
  and applies it to the wallpaper (both **light and dark** modes) using `gsettings`.
- A **systemd user service** runs the script on graphical-session login
  (`graphical-session.target`) — the point at which the session DBus already
  exists, which is what `gsettings` needs (this is why it doesn't rely on cron's
  `@reboot`).
- The script **retries** while waiting for the network to come up and, if it
  ultimately fails, keeps the current wallpaper instead of leaving a black screen.
- Every download is checked to be a **real, full-size image** before being
  applied — an HTTP 200 is not enough, since it may be an error page, and
  handing that to `gsettings` leaves you staring at GNOME's plain fallback
  background. Anything narrower than 800 px (e.g. a logo) is rejected too.
- On days when the APOD is a video there is no picture to use, so it **walks back
  one day at a time** until it finds an APOD that is an image.
- It keeps only the last 10 images in `~/.local/share/apod-wallpaper/`.

## Requirements

- Ubuntu / any distro running **GNOME** (other desktops, like KDE or XFCE, are
  not supported)
- `curl`, `jq`, `file`, `gsettings`, `systemd` (default on Ubuntu)

## Installation

```bash
git clone https://github.com/isaac-prado/apod-wallpaper.git
cd apod-wallpaper
./install.sh
```

**No account or API key needed.** From your next login on, the wallpaper becomes
the APOD of the day.

## Usage

```bash
# Run it manually right now
systemctl --user start apod-wallpaper.service

# View the last run's log
journalctl --user -u apod-wallpaper.service --since today

# Disable the automatic trigger
systemctl --user disable apod-wallpaper.service
```

## Configuration (optional)

The defaults work out of the box. These environment variables are supported by the script:

| Variable | Default | Description |
|---|---|---|
| `APOD_DIR` | `~/.local/share/apod-wallpaper` | Where to store the images |
| `APOD_RETRIES` | `30` | Attempts while waiting for the network |
| `APOD_RETRY_DELAY` | `5` | Seconds between attempts |
| `APOD_LOOKBACK` | `7` | How many days to walk back when the APOD has no usable image |
| `APOD_MIN_WIDTH` | `800` | Images narrower than this (px) are rejected |

## Uninstall

```bash
systemctl --user disable --now apod-wallpaper.service
rm ~/.local/bin/apod-wallpaper.sh ~/.config/systemd/user/apod-wallpaper.service
rm -r ~/.local/share/apod-wallpaper
systemctl --user daemon-reload
```

## Note

NASA's `api.nasa.gov/planetary/apod` currently returns the NASA logo instead of
the picture ([nasa/apod-api#184](https://github.com/nasa/apod-api/issues/184)),
which is why this uses the official RSS feed instead — and why no API key is needed.

## License

MIT
