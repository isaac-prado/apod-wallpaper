# apod-wallpaper

Automatically sets the **APOD** (NASA's Astronomy Picture of the Day) as your
**GNOME** desktop wallpaper every time you log in.

![desktop](https://img.shields.io/badge/desktop-GNOME-blue) ![shell](https://img.shields.io/badge/shell-bash-green)

## How it works

- A Bash script downloads the day's APOD via the [NASA API](https://api.nasa.gov)
  and applies it to the wallpaper (both **light and dark** modes) using `gsettings`.
- A **systemd user service** runs the script on graphical-session login
  (`graphical-session.target`) — the point at which the session DBus already
  exists, which is what `gsettings` needs (this is why it doesn't rely on cron's
  `@reboot`).
- The script **retries** while waiting for the network to come up and, if it
  ultimately fails, keeps the current wallpaper instead of leaving a black screen.
- On days when the APOD is a video → it uses the thumbnail.
- It keeps only the last 10 images in `~/.local/share/apod-wallpaper/`.

## Requirements

- Ubuntu / any distro running **GNOME**
- `curl`, `jq`, `gsettings`, `systemd` (default on Ubuntu)

## Installation

```bash
git clone https://github.com/isaac-prado/apod-wallpaper.git
cd apod-wallpaper
./install.sh
```

From your next login on, the wallpaper becomes the APOD of the day.

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

By default it uses NASA's `DEMO_KEY` (limit ~30 requests/hour — enough for
login). To use your own free key (https://api.nasa.gov), edit
`~/.config/systemd/user/apod-wallpaper.service` and uncomment:

```ini
Environment=APOD_API_KEY=YOUR_KEY_HERE
```

Then: `systemctl --user daemon-reload`.

Environment variables supported by the script:

| Variable | Default | Description |
|---|---|---|
| `APOD_API_KEY` | `DEMO_KEY` | NASA API key |
| `APOD_DIR` | `~/.local/share/apod-wallpaper` | Where to store the images |
| `APOD_RETRIES` | `30` | Attempts while waiting for the network |
| `APOD_RETRY_DELAY` | `5` | Seconds between attempts |

## License

MIT
