# ignisTab — Die perfekte Ergänzung für [ignis](https://github.com/EmergencyForge/ignis)

Mit **ignisTab** (vormals intraTab) lässt sich ignis ganz einfach auch in FiveM benutzen! Einfach die Ressource in das entsprechende Verzeichnis des FiveM-Servers ziehen, gewünschte Anpassungen an der `config.lua` vornehmen (wichtig: Der Link zur ignis-Installation) und startbereit ist die Ingame-Integration. Das System befindet sich aktuell in Entwicklung und wird stetig verändert.

> [!WARNING]
> Um ignisTab zu verwenden wird eine Installation von ignis zwingend benötigt!

## Installation

1. Neuestes Release-ZIP von der [Releases-Seite](https://github.com/EmergencyForge/ignisTab/releases) herunterladen
2. Den Ordner `ignisTab` in das `resources`-Verzeichnis des FiveM-Servers entpacken
3. In der `config.lua` mindestens `Config.BaseURL` anpassen und den API-Key aus ignis in der `config_server.lua` bei `ServerConfig.APIKey` eintragen
4. `ensure ignisTab` in die `server.cfg` eintragen

> [!IMPORTANT]
> Der API-Key gehört in die `config_server.lua`, nicht in die `config.lua`. Die `config.lua` lädt jeder Spieler mit der Ressource herunter, ein Key darin ist also für alle lesbar. Wer von einer älteren Version kommt, verschiebt den Key, löscht `Config.APIKey` aus der `config.lua` und erzeugt in ignis am besten einen neuen Key.

## Module

| Modul | Beschreibung |
| --- | --- |
| **eNOTF** | Rettungsdienst-Tablet mit direktem Zugriff auf das digitale Notfallprotokoll |
| **FireTab** | Feuerwehr-Tablet für die Einsatzverwaltung |
| **EMD-Sync** | Heartbeat-Synchronisierung von Fahrzeugen, Status und Lagemeldungen mit ignis |
| **eNOTF-Billing** | Schnittstelle für die Abrechnung freigegebener eNOTF-Protokolle |

![Release27122025](https://github.com/user-attachments/assets/e4c5c365-f7a3-4362-9547-3b0aaa3c7add)

## Tablet-Login

Der Discord-Login von ignis funktioniert im Spielbrowser nicht. Der Tablet-Login meldet Spieler deshalb über die Discord-ID an, die der FiveM-Server von ihnen kennt:

1. Beim ersten Öffnen eines Tablets fragt der FiveM-Server bei ignis einen Login-Token für die Discord-ID des Spielers an.
2. ignis sucht das aktive Konto mit dieser Discord-ID. Der Token gilt 60 Sekunden und nur für eine Anmeldung.
3. Den Login-Link bekommt nur dieser Spieler. Das Tablet öffnet ihn und springt danach auf seine eigentliche Seite zurück.

Der API-Key bleibt dabei auf dem Server. Neue Konten legt der Tablet-Login nicht an. Ein Login gilt für beide Tablets, sie teilen sich die ignis-Sitzung. Klappt die Anmeldung nicht, bekommt der Spieler einen Hinweis und sieht die normale Login-Seite. Bei vorübergehenden Fehlern (zu viele Versuche, ignis nicht erreichbar) versucht es das Tablet beim nächsten Öffnen erneut. Bei dauerhaften Fehlern (keine Discord-ID, kein passendes Konto, Tablet-Login in ignis aus) kommt der Hinweis einmal pro Sitzung. Der Server nimmt pro Spieler höchstens eine Anfrage alle 15 Sekunden an.

Voraussetzungen:

- In ignis ist die Systemeinstellung `TABLET_LOGIN_ENABLED` eingeschaltet und ein API-Key gesetzt.
- Derselbe Key steht in der `config_server.lua` bei `ServerConfig.APIKey`.
- Der FiveM-Server setzt Discord als Identifier voraus. Nur dann liefert FiveM eine geprüfte Discord-ID.
- In der `config.lua` steht `Config.TabletLogin.Enabled = true`.

## Tests

Die Prüfskripte für den Tablet-Login laufen ohne FiveM, aus dem Repo-Root:

```
lua tests/tablet_login_check.lua   # Lua 5.4, Server und Client mit gestubbten Natives
node tests/nui_check.js            # NUI (master.js und die Tablet-Skripte)
```
