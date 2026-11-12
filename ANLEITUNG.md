# Installationsanleitung Smart-Waste-Prototyp

Diese Anleitung beschreibt, wie der komplette Prototyp auf einem einzelnen Server aufgesetzt wird:

| Schicht | Software | Port | Compose-Datei |
|---|---|---|---|
| Verwaltung | Portainer | 9443 | – (per `docker run`) |
| Kommunikation | Mosquitto (MQTT) | 1883 | `Docker/Docker_Compose_Kommunikation_MQTT.yaml` |
| Datensicherung | TimescaleDB + Adminer | 5432 / 8080 | `Docker/Docker_Compose_Datensicherung.yaml` |
| Datenverarbeitung | n8n | 5678 | `Docker/Docker_Compose_Verarbeitung_n8n.yaml` |
| Visualisierung | Grafana | 3000 | `Docker/Docker_Compose_Visualiesierung_Grafana.yaml` |

Im Folgenden steht `<SERVER-IP>` für die IP-Adresse des Docker-Hosts.

> **Hinweis zu Passwörtern:** Die Compose-Dateien enthalten einfache Standardpasswörter (z. B. `admin123`). Für einen Test im lokalen Netz ist das in Ordnung. Wenn der Server aus dem Internet erreichbar ist, ändere sie vor dem ersten Start.

---

## 0. Voraussetzungen

- Ein Linux-Server, z. B. eine Debian- oder Ubuntu-VM bzw. LXC unter Proxmox
  - mind. 2 CPU-Kerne, 4 GB RAM, 20 GB Speicher
  - bei einer **LXC** unter Proxmox: in den Container-Optionen *Features → nesting* aktivieren, sonst läuft Docker nicht
- Root-Zugang per Konsole oder SSH
- Dieses Repository lokal (für die Compose-Dateien, das SQL-Skript und den n8n-Flow)

---

## 1. Docker und Portainer installieren

### 1.1 Docker installieren

```bash
apt update && apt install -y curl
curl -fsSL https://get.docker.com | sh
docker --version          # Kontrolle
```

### 1.2 Portainer starten

```bash
docker volume create portainer_data

docker run -d \
  --name portainer \
  --restart=always \
  -p 8000:8000 -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

### 1.3 Ersteinrichtung

1. `https://<SERVER-IP>:9443` im Browser öffnen. Die Zertifikatswarnung ist normal (selbst signiertes Zertifikat).
2. Admin-Benutzer und Passwort anlegen. **Das muss innerhalb von ca. 5 Minuten nach dem Start passieren**, sonst sperrt sich Portainer. Dann einfach `docker restart portainer` ausführen.
3. *Get Started* → Umgebung **local** auswählen.

> **Passwort vergessen?**
> ```bash
> docker stop portainer
> docker run --rm -v portainer_data:/data portainer/helper-reset-password
> docker start portainer
> ```
> Das neue Passwort steht in der Ausgabe.

---

## 2. Stacks mit Docker Compose anlegen

Jede Compose-Datei wird in Portainer als eigener **Stack** angelegt:

1. Links **Stacks** → **+ Add stack**
2. Namen vergeben (nur Kleinbuchstaben, Zahlen, `-`, `_`), z. B. `datensicherung`
3. **Web editor** auswählen und den Inhalt der Compose-Datei einfügen
4. Platzhalter anpassen (siehe unten)
5. **Deploy the stack**

Empfohlene Reihenfolge:

| # | Stack-Name | Datei | Was vorher anpassen |
|---|---|---|---|
| 1 | `datensicherung` | `Docker_Compose_Datensicherung.yaml` | optional `POSTGRES_PASSWORD` |
| 2 | `mqtt` | `Docker_Compose_Kommunikation_MQTT.yaml` | nichts |
| 3 | `n8n` | `Docker_Compose_Verarbeitung_n8n.yaml` | siehe 2.1 |
| 4 | `grafana` | `Docker_Compose_Visualiesierung_Grafana.yaml` | `GF_SECURITY_ADMIN_PASSWORD` |

Danach sollten unter **Containers** alle Container mit Status *running* erscheinen.

> Eine Warnung wie *„the attribute `version` is obsolete“* kann ignoriert werden.

### 2.1 Platzhalter im n8n-Stack

| Variable | Wert |
|---|---|
| `N8N_ENCRYPTION_KEY` | einmalig erzeugen mit `openssl rand -hex 32`. **Gut aufbewahren**: Ohne diesen Schlüssel können gespeicherte n8n-Zugangsdaten nicht mehr entschlüsselt werden. |
| `N8N_HOST` | `<SERVER-IP>` oder Domain |
| `N8N_PROTOCOL` | `http`, solange kein Reverse-Proxy mit HTTPS davor läuft |
| `WEBHOOK_URL` | vollständige URL, z. B. `http://<SERVER-IP>:5678/` |
| `N8N_BASIC_AUTH_*` | können entfernt werden. Ab n8n 1.0 wird der Login beim ersten Aufruf angelegt (siehe 5.1). |

### 2.2 Wie die Container sich gegenseitig erreichen

Jeder Stack bekommt ein eigenes Docker-Netzwerk. Die Dienste erreichen sich deshalb **nicht** über ihren Containernamen, sondern über die **IP des Servers** und den veröffentlichten Port:

- Datenbank: `<SERVER-IP>:5432`
- MQTT-Broker: `<SERVER-IP>:1883`

Diese Adressen werden in n8n und Grafana eingetragen.

---

## 3. Tabellen in Adminer anlegen

1. `http://<SERVER-IP>:8080` öffnen und anmelden:

   | Feld | Wert |
   |---|---|
   | System | PostgreSQL |
   | Server | `timescaledb` |
   | Benutzer | `admin` |
   | Passwort | `admin123` (bzw. dein Wert aus dem Stack) |
   | Datenbank | `sensordata` |

2. Links **SQL-Kommando** öffnen.
3. Den Inhalt von `Datensicherung - PostgreSQL + Adminer/schema_sensordata.sql` einfügen. Alternativ unter **Importieren** die Datei hochladen.
4. **Ausführen** klicken.

Anschließend erscheinen links diese Tabellen:

| Tabelle | Inhalt |
|---|---|
| `sensor_data` | Stammdaten je Sensor (Standort, Typ, Volumen, Gebäude/Raum) |
| `sensor_fill_level` | Füllstandsmessungen (TimescaleDB-Hypertable) |
| `sensor_last_empty` | erkannte Leerungen (TimescaleDB-Hypertable) |
| `sensor_avg_fill_rate` | berechnete Füllrate und Prognose „voll am …“ |
| `sensor_daily_delta` | tägliche Zuwächse für die Simulation |
| `sensor_cost` | Kostenparameter je Müllart |
| `sensor_cost_history` | Kostenverlauf je Sensor |
| `routes` | berechnete Abholrouten |

> **Fehler „extension timescaledb …“?** Die Erweiterung ist im verwendeten Image enthalten. Prüf, ob im Stack wirklich `timescale/timescaledb:latest-pg15` steht.

> Das Skript ist nur für eine **leere** Datenbank gedacht. Ein zweiter Durchlauf bricht mit „relation already exists“ ab.

---

## 4. MQTT-Account anlegen

Mosquitto 2 lässt standardmäßig keine anonymen Verbindungen von außen zu. Deshalb werden einmalig eine Konfiguration und ein Benutzer angelegt. Die Befehle laufen auf dem Server (Konsole bzw. SSH).

### 4.1 Konfiguration schreiben

```bash
docker exec mosquitto sh -c 'cat > /mosquitto/config/mosquitto.conf <<EOF
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF'
```

### 4.2 Benutzer anlegen

```bash
# Benutzer "sensor" anlegen, das Passwort wird zweimal abgefragt
docker exec -it mosquitto mosquitto_passwd -c /mosquitto/config/passwd sensor

# Rechte setzen, sonst warnt Mosquitto beim Start
docker exec mosquitto sh -c 'chown mosquitto:mosquitto /mosquitto/config/passwd && chmod 0700 /mosquitto/config/passwd'

docker restart mosquitto
```

Weitere Benutzer legst du **ohne** `-c` an, sonst wird die Datei überschrieben:

```bash
docker exec -it mosquitto mosquitto_passwd /mosquitto/config/passwd n8n
docker restart mosquitto
```

### 4.3 Testen

In einem Terminal mitlesen:

```bash
docker exec -it mosquitto mosquitto_sub -h localhost -u sensor -P '<PASSWORT>' -t 'trashsensor/#' -v
```

In einem zweiten Terminal senden:

```bash
docker exec mosquitto mosquitto_pub -h localhost -u sensor -P '<PASSWORT>' -t 'trashsensor/test' -m 'hallo'
```

Wenn im ersten Terminal `trashsensor/test hallo` erscheint, funktioniert der Broker.

---

## 5. n8n-Flow importieren und anpassen

### 5.1 Ersteinrichtung

`http://<SERVER-IP>:5678` öffnen und den Owner-Account anlegen.

### 5.2 Zugangsdaten (Credentials) anlegen

Links **Credentials** → **Add credential**:

| Credential | Typ | Einstellungen |
|---|---|---|
| TimescaleDB | *TimescaleDB* | Host `<SERVER-IP>`, Port `5432`, Database `sensordata`, User `admin`, Passwort aus dem Stack, SSL `disable` |
| MQTT Broker | *MQTT* | Protocol `mqtt`, Host `<SERVER-IP>`, Port `1883`, Benutzer/Passwort aus Schritt 4 |
| openrouteservice | *Header Auth* | Name `Authorization`, Value = dein API-Key von [openrouteservice.org](https://openrouteservice.org/dev/#/signup) |
| *optional* MQTT TTN | *MQTT* | Zugang zu The Things Network (Host `eu1.cloud.thethings.network`, Benutzer = Application-ID, Passwort = API-Key aus der TTN-Konsole) |
| *optional* MQTT ChirpStack | *MQTT* | Zugang zum ChirpStack-Broker des Netzbetreibers |
| *optional* Gmail / Google Drive | *Gmail OAuth2* / *Google Drive OAuth2* | nur für den Berichtsversand |

### 5.3 Workflow importieren

1. **Workflows** → **+** (neuer Workflow) → Menü **⋯** oben rechts → **Import from File…**
2. `n8n/smart_trash_bereinigt.json` auswählen.
3. Jeden Node mit rotem Warnsymbol öffnen und unter *Credential* das passende Credential aus 5.2 auswählen.

### 5.4 Platzhalter ersetzen

Im Flow wurden private Daten durch Platzhalter ersetzt. Diese müssen angepasst werden:

| Platzhalter | Node(s) | Ersetzen durch |
|---|---|---|
| `<ORS_API_KEY>` | `openrouteservice API optimise`, `openrouteserivce API directions`, `openrouteserivce API directions as Geojson` | Besser: Header-Zeile `Authorization` löschen und unter *Authentication → Generic → Header Auth* das Credential „openrouteservice“ wählen. Dann steht der Key nicht im Workflow. |
| `<EMPFAENGER_EMAIL>` | `Send a message`, `Send a message1` | Empfängeradresse für Benachrichtigungen bzw. den Müllbericht |
| `[0.0, 0.0] /* <START_LON>, <START_LAT> */` | `Code` (Routenplanung) | Startpunkt der Abholtour als `[Längengrad, Breitengrad]`, z. B. Betriebshof |
| `<DRIVE_FOLDER_ID>` | `Upload file` | Zielordner in Google Drive (oder den Node löschen) |
| `<WEBHOOK_PATH>` | `Webhook` | beliebiger Pfad, z. B. `muellbericht` |

Außerdem anpassen:

- **MQTT-Topic:** Der Node `MQTT Trigger - Berlin` hört auf `trashsensor/salt`. Trag hier das Topic ein, auf dem deine Sensoren senden (z. B. `trashsensor/#` für alle).
- **Nicht genutzte Trigger deaktivieren:** Der Flow hat drei Eingänge: eigener Broker (`MQTT Trigger - Berlin`), ChirpStack (`MQTT Trigger`) und TTN (`MQTT Trigner TTN`). Nicht benötigte Trigger per Rechtsklick → *Deactivate* abschalten, sonst schlägt die Aktivierung wegen fehlender Zugangsdaten fehl.
- **Schwellwert für Routen:** Der Node `sensor über 50` plant Routen ab `fill_level >= 45`. Bei Bedarf anpassen.

### 5.5 Aktivieren

Speichern und oben rechts den Schalter auf **Active** stellen.

### 5.6 Was der Flow macht

| Bereich | Auslöser | Funktion |
|---|---|---|
| Neue Sensordaten | MQTT | Nachricht parsen, Füllstand in `sensor_fill_level` speichern, unbekannte Sensoren in `sensor_data` anlegen (mit E-Mail-Benachrichtigung) |
| Leerung erkennen | nach jedem Messwert | Fällt der Füllstand um mehr als 20 Prozentpunkte, wird ein Eintrag in `sensor_last_empty` geschrieben |
| Füllrate | nach jedem Messwert | Durchschnittliche Füllrate und voraussichtlicher Zeitpunkt „voll“ → `sensor_avg_fill_rate` |
| Simulation | Zeitplan | Tageswerte aus `sensor_daily_delta` werden zu Füllständen hochgerechnet |
| Routenplanung | täglich 5 Uhr | Volle Behälter abfragen, optimierte Reihenfolge per openrouteservice → `routes` |
| Bericht | Webhook oder Mail mit Betreff „Müllaufkommen“ | Müllaufkommen je Standort als Excel-Datei per Mail und nach Google Drive |

---

## 6. Grafana einrichten

### 6.1 Login

`http://<SERVER-IP>:3000` öffnen. Benutzer `admin`, Passwort aus `GF_SECURITY_ADMIN_PASSWORD`.

### 6.2 Datenquelle anlegen

**Connections → Data sources → Add data source → PostgreSQL**

| Feld | Wert |
|---|---|
| Host URL | `<SERVER-IP>:5432` |
| Database name | `sensordata` |
| Username / Password | `admin` / Passwort aus dem Stack |
| TLS/SSL Mode | `disable` |
| TimescaleDB | aktivieren |

**Save & test** muss „Database Connection OK“ melden.

Danach in der Adresszeile die **UID** der Datenquelle notieren. Sie steht am Ende der URL, z. B. `…/datasources/edit/abc123xyz`.

### 6.3 Dashboards importieren

Die Dashboards im Repository verweisen auf die Datenquellen-UID des Originalsystems (`cf0g6y32klfy8f` bzw. `xxx`). Diese muss vor dem Import ersetzt werden:

```bash
sed -i 's/cf0g6y32klfy8f/<DEINE-UID>/g' dashboard_simulation_config.json
sed -i 's/"uid": "xxx"/"uid": "<DEINE-UID>"/g' "dashboard Bildungseinrichtung"
```

Dann **Dashboards → New → Import → Upload dashboard JSON file** und die Dateien hochladen:

- `dashboard_simulation_config.json`: Simulation und Kostenvergleich statisch vs. dynamisch
- `dashboard Bildungseinrichtung`: Übersicht für Bildungseinrichtungen

> Ohne den UID-Tausch zeigen die Panels „Datasource not found“. Alternativ kannst du in jedem Panel unter *Edit* die Datenquelle manuell neu auswählen.

---

## 7. Gesamttest

Eine Testnachricht im Format des Flows `MQTT Trigger - Berlin` senden:

```bash
docker exec mosquitto mosquitto_pub -h localhost -u sensor -P '<PASSWORT>' \
  -t 'trashsensor/salt' \
  -m '{"id":"Test001","time":"2026-01-01T10:00:00Z","percent":42,"distance":58,"lon":13.40,"lat":52.52,"location":"Testcampus","type":"Restmüll","volumen_in_l":1100}'
```

Anschließend prüfen:

1. **n8n** → *Executions*: Die Ausführung muss grün sein.
2. **Adminer**: In `sensor_data` steht der Sensor `Test001`, in `sensor_fill_level` der Messwert.
3. **Grafana**: Der Sensor erscheint in den Dashboards.

---

## 8. Fehlersuche

| Problem | Lösung |
|---|---|
| Container startet nicht | Portainer → Container → **Logs** |
| n8n erreicht die Datenbank nicht | Als Host die Server-IP eintragen, nicht `localhost` oder `timescaledb` (anderes Docker-Netzwerk, siehe 2.2) |
| MQTT: „Connection refused: not authorised“ | Benutzer/Passwort prüfen, nach Änderungen `docker restart mosquitto` |
| n8n-Login: „secure cookie“-Fehler | `N8N_SECURE_COOKIE=false` muss gesetzt sein, solange ohne HTTPS gearbeitet wird |
| n8n-Credentials nach Neuinstallation unlesbar | Es wurde ein anderer `N8N_ENCRYPTION_KEY` verwendet. Den ursprünglichen Schlüssel wieder eintragen. |
| Portainer: „timed out for security purposes“ | `docker restart portainer`, dann innerhalb von 5 Minuten den Admin anlegen |
