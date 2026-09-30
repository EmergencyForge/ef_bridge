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
