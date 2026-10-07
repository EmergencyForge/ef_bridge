# ef_bridge

FiveM-Ressource von EmergencyForge, die den Spielserver mit [ignis](https://github.com/EmergencyForge/ignis) und Lex verbindet. Vormals ignisTab (davor intraTab).

Für ignis bringt ef_bridge das eNOTF-Tablet und das FireTab ins Spiel, gleicht Fahrzeuge, Status und Lagemeldungen mit `emergencydispatch` ab und reicht freigegebene eNOTF-Protokolle an ein Abrechnungsskript weiter. Für Lex meldet ef_bridge die Charaktere als Personen und ihre Fahrzeuge samt Halter.

Jedes Modul lässt sich einzeln einschalten. Wer nur Lex nutzt, braucht keine ignis-Installation, und umgekehrt. Config-Dateien gibt es nicht: eingestellt wird alles im Spiel im Admin-Panel oder in der Serverkonsole.

## Installation

Die ausführliche Anleitung mit allen Einstellungen, Rechten und Hilfe bei Problemen steht in der [INSTALL.md](INSTALL.md). Kurz:

1. Neuestes Release-ZIP von der [Releases-Seite](https://github.com/EmergencyForge/ignisTab/releases) herunterladen
2. Den Ordner `ef_bridge` in das `resources`-Verzeichnis des FiveM-Servers entpacken
3. `ensure ef_bridge` und `add_ace group.admin ef_bridge.admin allow` in die `server.cfg` eintragen
4. Server starten, im Spiel `/efbridge` öffnen und Adressen, API-Schlüssel und die gewünschten Module eintragen

Wer von ignisTab kommt, legt seine alte `config.lua` und `config_server.lua` in den neuen Ordner: ef_bridge übernimmt sie beim ersten Start. Mehr dazu unter [Umstieg von ignisTab](INSTALL.md#umstieg-von-ignistab).

## Module

| Modul | Gegenstelle | Was es tut |
| --- | --- | --- |
| eNOTF-Tablet | ignis | Rettungsdienst-Tablet mit dem digitalen Notfallprotokoll |
| FireTab | ignis | Feuerwehr-Tablet für die Einsatzverwaltung |
| EMD-Sync | ignis | Fahrzeuge, Status, Einsatzdaten und Lagemeldungen zwischen `emergencydispatch` und ignis |
| eNOTF-Abrechnung | ignis | freigegebene eNOTF-Protokolle für das eigene Abrechnungsskript |
| Lex-Abgleich | Lex | Charaktere als Personen, eigene Fahrzeuge mit Halter |

![Release27122025](https://github.com/user-attachments/assets/e4c5c365-f7a3-4362-9547-3b0aaa3c7add)

## Admin-Panel

`/efbridge` öffnet im Spiel ein Panel mit dem Zustand aller Module und allen Einstellungen. Es braucht das ACE-Recht `ef_bridge.admin`. Änderungen gelten sofort, ein paar (Chatbefehle, Standardtasten, Framework, Statustabelle) erst nach `restart ef_bridge`; das Panel markiert sie. Der Server speichert alles in seinem KVP-Speicher, es überlebt also einen Neustart und ein Update, das den Ordner ersetzt. Pro Einstellung lässt sich auf den Standard zurückschalten.

API-Schlüssel lassen sich im Panel setzen und löschen, angezeigt werden sie nie wieder, und sie verlassen den Server nicht. Unter **Import** übernimmt das Panel alte config-Dateien von ignisTab per Einfügen, mit Vorschau vor dem Übernehmen.

Dasselbe geht über die Serverkonsole, auch bevor jemand auf dem Server ist:

```
efbridge status
efbridge set Ignis.BaseURL https://ignis.example.de/
efbridge key ignis <Schlüssel>
efbridge set Tablets.eNOTF.AllowedJobs ambulance,doj
efbridge import          # config.lua / config_server.lua aus dem Ordner
efbridge export          # Einstellungen ohne Schlüssel nach settings-export.json
efbridge test
```

## Lex-Abgleich

ef_bridge liest Charaktere und Fahrzeuge aus der Framework-Datenbank, nicht nur von Spielern, die gerade online sind:

| Framework | Charaktere | Fahrzeuge |
| --- | --- | --- |
| QBCore, Qbox | `players` (citizenid, charinfo) | `player_vehicles`, Modellname aus `QBCore.Shared.Vehicles` |
| ESX | `users` (identifier, Name, Geburtsdatum, Geschlecht, `phone_number` falls vorhanden) | `owned_vehicles`, Modellname aus der Tabelle `vehicles` von esx_vehicleshop |

Ein Charakter, der sich einloggt, geht nach wenigen Sekunden samt Fahrzeugen an Lex. Dazu kommt ein vollständiger Abgleich beim Start und alle sechs Stunden (einstellbar). Lex legt Personen an oder bringt sie auf Stand, verknüpft von Hand angelegte Personen mit gleichem Namen und Geburtsdatum, statt sie doppelt anzulegen, und setzt den Halter. Fahrzeuge, die der vollständige Abgleich nicht mehr findet, meldet Lex ab. Adresse, Foto, Notizen und Akten in Lex fasst der Abgleich nicht an.

Andere Skripte melden Änderungen sofort statt mit dem nächsten Abgleich, zum Beispiel nach einem Fahrzeugkauf:

```lua
exports.ef_bridge:LexSyncCharacter(source)       -- oder eine Citizen-ID / ESX-Identifier
exports.ef_bridge:LexFullSync()
```

Schlüssel und Adresse zeigt Lex unter Einstellungen › FiveM-Abgleich, eingetragen werden sie im Panel unter Lex.

## Tablet-Login

Der Discord-Login von ignis funktioniert im Spielbrowser nicht. Der Tablet-Login meldet Spieler deshalb über die Discord-ID an, die der FiveM-Server von ihnen kennt:

1. Beim ersten Öffnen eines Tablets fragt der FiveM-Server bei ignis einen Login-Token für die Discord-ID des Spielers an.
2. ignis sucht das aktive Konto mit dieser Discord-ID. Der Token gilt 60 Sekunden und nur für eine Anmeldung.
3. Den Login-Link bekommt nur dieser Spieler. Das Tablet öffnet ihn und springt danach auf seine eigentliche Seite zurück.

Der API-Key bleibt dabei auf dem Server. Neue Konten legt der Tablet-Login nicht an. Ein Login gilt für beide Tablets, sie teilen sich die ignis-Sitzung. Klappt die Anmeldung nicht, bekommt der Spieler einen Hinweis und sieht die normale Login-Seite. Bei vorübergehenden Fehlern (zu viele Versuche, ignis nicht erreichbar) versucht es das Tablet beim nächsten Öffnen erneut. Bei dauerhaften Fehlern (keine Discord-ID, kein passendes Konto, Tablet-Login in ignis aus) kommt der Hinweis einmal pro Sitzung. Der Server nimmt pro Spieler höchstens eine Anfrage alle 15 Sekunden an.

Voraussetzungen:

- In ignis ist die Systemeinstellung `TABLET_LOGIN_ENABLED` eingeschaltet und ein API-Key gesetzt.
- Derselbe Key ist in ef_bridge eingetragen (Panel unter ignis oder `efbridge key ignis <Schlüssel>`).
- Der FiveM-Server setzt Discord als Identifier voraus. Nur dann liefert FiveM eine geprüfte Discord-ID.
- In ef_bridge ist „Tablet-Login über Discord-ID“ eingeschaltet (`Ignis.TabletLogin`).

## Tests

Die Prüfskripte laufen ohne FiveM, aus dem Repo-Root:

```
lua tests/tablet_login_check.lua   # Lua 5.4: Tablet-Login, Identify, Abrechnung, Client
lua tests/bridge_check.lua         # Lua 5.4: Einstellungen, Import, Admin-Panel, Lex-Abgleich
node tests/nui_check.js            # NUI (master.js und die Tablet-Skripte)
```
