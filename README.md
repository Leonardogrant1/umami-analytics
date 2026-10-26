# umami-analytics

Selbst gehostetes [Umami](https://umami.is) (privacy-freundliche Web-Analytics) per
Docker Compose auf einem DigitalOcean-Droplet — als Analytics-Backend für die
Link-in-Bio-Seite auf **leonardogranetto.com**.

**Stack:** Umami + Postgres 16 + Caddy (Reverse Proxy mit automatischem HTTPS).
Nur Caddy ist von außen erreichbar (80/443); Umami und Postgres bleiben im
internen Docker-Netz.

```
Browser ──HTTPS──▶ Caddy ──▶ umami:3000 ──▶ db:5432 (Postgres)
```

---

## 1. Droplet anlegen

- DigitalOcean → Droplet erstellen
- **Image:** Ubuntu 24.04 LTS
- **Größe:** der kleinste Shared-CPU-Plan reicht locker (1 vCPU / 1 GB RAM,
  ~6 $/Monat). Umami ist genügsam; bei 1 GB RAM ggf. 1 GB Swap einrichten.
- **Auth:** SSH-Key hinterlegen (kein Passwort-Login)

## 2. Server absichern

Als root per SSH verbinden, dann:

```bash
# Non-root-User mit sudo anlegen
adduser leo
usermod -aG sudo leo
rsync --archive --chown=leo:leo ~/.ssh /home/leo

# Firewall: nur SSH, HTTP, HTTPS
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp   # HTTP/3
ufw enable

# Docker + Compose-Plugin (offizielles Install-Script)
curl -fsSL https://get.docker.com | sh
usermod -aG docker leo
```

Danach als `leo` neu einloggen und root-SSH-Login deaktivieren
(`PermitRootLogin no` in `/etc/ssh/sshd_config`, dann `sudo systemctl restart ssh`).

> Hinweis: Docker published Ports an der Firewall vorbei (iptables). In diesem
> Setup öffnet aber nur Caddy Ports — genau die, die ufw ohnehin erlaubt.

## 3. DNS

Beim DNS-Provider einen **A-Record** anlegen:

```
analytics.leonardogranetto.com  →  <Droplet-IP>
```

Propagation prüfen: `dig +short analytics.leonardogranetto.com` muss die
Droplet-IP liefern, **bevor** du die Container startest (sonst scheitert das
Let's-Encrypt-Zertifikat, siehe Troubleshooting).

## 4. Repo klonen & starten

```bash
git clone <repo-url> umami-analytics
cd umami-analytics

cp .env.example .env
# Secrets erzeugen und in .env eintragen:
openssl rand -hex 32      # → DB_PASSWORD (hex, NICHT base64 — landet in der DATABASE_URL)
openssl rand -base64 32   # → APP_SECRET
openssl rand -hex 32      # → TWO_FACTOR_ENCRYPTION_KEY (optional, für 2FA)

docker compose up -d
docker compose ps         # alle Services sollten "healthy" / "running" sein
```

## 5. Erster Login

`https://analytics.leonardogranetto.com` öffnen und mit dem Standard-Zugang
einloggen:

- **Benutzer:** `admin`
- **Passwort:** `umami`

**Sofort ändern:** Profil (oben rechts) → Passwort ändern.

## 6. Website anlegen & Tracking einbinden

1. In Umami: **Settings → Websites → Add website**, Name und Domain
   (`leonardogranetto.com`) eintragen.
2. Umami zeigt dir den Tracking-Snippet mit der Website-ID. Mit dem in der
   `.env` gesetzten `TRACKER_SCRIPT_NAME=stats` sieht er so aus:

```html
<script defer src="https://analytics.leonardogranetto.com/stats"
        data-website-id="DEINE-WEBSITE-ID"></script>
```

Das Script in den `<head>` der Link-Seite einbauen — fertig. Details zum
Event-Tracking: siehe [Bonus-Abschnitt](#bonus-tracking-auf-der-link-in-bio-seite).

## 7. Betrieb

### Backups

`scripts/backup.sh` erstellt ein komprimiertes `pg_dump`-Backup unter
`backups/` und behält automatisch die letzten 14 Stück.

Cronjob einrichten (täglich 03:30 Uhr):

```bash
crontab -e
# Zeile einfügen (Pfad anpassen):
30 3 * * * /home/leo/umami-analytics/scripts/backup.sh >> /home/leo/umami-backup.log 2>&1
```

Restore bei Bedarf:

```bash
./scripts/restore.sh backups/umami-2026-10-26_0330.sql.gz
```

> Die Backups liegen auf demselben Server. Für echte Sicherheit regelmäßig
> nach extern kopieren (z. B. `rsync` auf den eigenen Rechner oder ein
> DigitalOcean Space).

### Updates

```bash
./scripts/backup.sh   # sicher ist sicher
./scripts/update.sh   # pull, neu starten, alte Images aufräumen
```

### Logs

```bash
docker compose logs -f           # alles
docker compose logs -f umami     # nur Umami
docker compose logs -f caddy     # nur Caddy (z. B. bei Zertifikatsproblemen)
```

## 8. Troubleshooting

**Zertifikat schlägt fehl / Seite nicht erreichbar**
Meist ist der DNS-Eintrag noch nicht propagiert. Prüfen mit
`dig +short analytics.leonardogranetto.com` — kommt nicht die Droplet-IP,
warten. Caddy versucht es automatisch erneut; Details in
`docker compose logs caddy`. Außerdem prüfen: Ports 80/443 in ufw offen?

**Container startet nicht / Restart-Loop**
`docker compose ps` zeigt den Status, `docker compose logs <service>` den
Grund. Häufige Ursachen:

- `.env` fehlt oder `DB_PASSWORD`/`APP_SECRET` sind leer
- `DB_PASSWORD` wurde **nach** dem ersten Start geändert — Postgres behält das
  alte Passwort im Volume. Entweder zurückändern oder (Datenverlust!) Volume
  löschen: `docker compose down -v`
- Zu wenig RAM: `free -h` prüfen, ggf. Swap einrichten

**Umami bleibt "unhealthy"**
Umami wartet beim Start auf die Datenbank-Migration — beim allerersten Start
kann das eine Minute dauern (`start_period` im Healthcheck fängt das ab).
Bleibt es dabei: `docker compose logs umami`.

---

## Bonus: Tracking auf der Link-in-Bio-Seite

Ziel: Seitenaufrufe, Klicks pro Button und Herkunft über `?ref=ig` /
`?ref=tiktok` / `?ref=x` messen — und den ref als `utm_source` an den
JEMP-Link weiterreichen.

```html
<head>
  <!-- Umami-Tracking (zählt automatisch Seitenaufrufe inkl. Query-String,
       d. h. ?ref=ig taucht in Umami direkt als eigene URL auf) -->
  <script defer src="https://analytics.leonardogranetto.com/stats"
          data-website-id="DEINE-WEBSITE-ID"></script>
</head>
<body>
  <!-- Klick-Events: einfach data-umami-event aufs Element setzen.
       Mit data-umami-event-* lassen sich Zusatzdaten anhängen. -->
  <a id="jemp-link" href="https://jemp.example.com"
     data-umami-event="click-jemp">JEMP</a>

  <a href="https://instagram.com/..."
     data-umami-event="click-instagram">Instagram</a>

  <a href="https://tiktok.com/@..."
     data-umami-event="click-tiktok">TikTok</a>

  <script>
    // ?ref aus der URL lesen (z. B. leonardogranetto.com?ref=ig)
    const ref = new URLSearchParams(location.search).get('ref');

    if (ref) {
      // 1. ref als utm_source an den JEMP-Link weiterreichen,
      //    damit die Herkunft auch dort ankommt
      const jemp = document.getElementById('jemp-link');
      const url = new URL(jemp.href);
      url.searchParams.set('utm_source', ref);
      jemp.href = url.toString();

      // 2. ref zusätzlich an alle Klick-Events hängen —
      //    in Umami dann pro Event nach "ref" filterbar
      document.querySelectorAll('[data-umami-event]').forEach((el) => {
        el.setAttribute('data-umami-event-ref', ref);
      });
    }
  </script>
</body>
```

In Umami findest du die Klicks dann unter **Events** (z. B. `click-jemp`),
die Herkunft entweder über die Seiten-URLs (`/?ref=ig`) oder als
Event-Property `ref` an jedem Klick.
