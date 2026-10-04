# ignisTab installieren

ignisTab bringt ignis als Tablet in deinen FiveM-Server: ein eNOTF-Tablet für den Rettungsdienst und ein FireTab für die Feuerwehr. Dazu kommen auf Wunsch der Abgleich mit dem Einsatzleitsystem (EMD-Sync) und die Abrechnung freigegebener eNOTF-Protokolle.

ignisTab ist nur die Brücke ins Spiel. Du brauchst eine laufende ignis-Installation, die Anleitung dafür findest du im [ignis-Repository](https://github.com/EmergencyForge/ignis/blob/main/INSTALL.md).


## Was du brauchst

**Auf dem FiveM-Server**

- ein aktuelles FiveM-Server-Build (Artifacts)
- QBCore oder ESX. Ohne eines der beiden Frameworks lässt sich das Tablet nicht öffnen, weil ignisTab Name, Job und Charakter von dort holt.
- `ox_inventory`, wenn das Tablet nur mit einem Gegenstand im Inventar funktionieren soll (optional, QBCore- und ESX-Inventare gehen auch)
- `oxmysql`, wenn du EMD-Sync oder die eNOTF-Abrechnung nutzt
- `emergencydispatch`, wenn du EMD-Sync nutzt

**Bei ignis**

- ignis ab Version 2026.0.14-beta, für die eNOTF-Abrechnung ab 2026.0.26-beta
- ignis muss über **HTTPS mit gültigem Zertifikat** erreichbar sein, und zwar sowohl für die Spieler als auch vom FiveM-Server aus. ignisTab baut alle Adressen mit `https://` auf.
- das Plugin **eNOTF** ist eingeschaltet (für das eNOTF-Tablet), das Plugin **fireTab** ebenfalls (für das FireTab)


## Installation

### 1. Herunterladen und entpacken

Lade auf der [Release-Seite](https://github.com/EmergencyForge/ignisTab/releases) die neueste ZIP-Datei herunter und entpack sie in den `resources`-Ordner deines Servers. Danach gibt es einen Ordner `resources/ignisTab`.

Behalte den Ordnernamen `ignisTab` bei. Andere Skripte sprechen ignisTab über `exports['ignisTab']` an. Kommst du von einer älteren Version mit dem Ordner `intraTab`, benenn ihn um und pass die `server.cfg` an.

### 2. Adresse von ignis eintragen

Öffne `config.lua` und trag die Adresse deiner ignis-Installation ein, mit `/` am Ende:

```lua
Config.BaseURL = 'https://ignis.example.de/'
```

Liegt ignis in einem Unterordner, gehört er dazu, zum Beispiel `https://example.de/ignis/`.

### 3. API-Schlüssel eintragen

Den Schlüssel findest du in ignis unter **Einstellungen › System-Konfiguration › Technik › API-Schlüssel**. Er wird bei der Installation von ignis erzeugt, mit dem Auge-Symbol blendest du ihn ein.

Trag ihn in `config_server.lua` ein:

```lua
ServerConfig.APIKey = 'dein-schluessel-aus-ignis'
```

> Der Schlüssel gehört **nur** in `config_server.lua`. Die `config.lua` lädt jeder Spieler mit der Ressource herunter, ein Schlüssel darin wäre für alle lesbar. Hast du ihn früher in der `config.lua` stehen gehabt, lösch ihn dort und erzeug in ignis einen neuen.

Erzeugst du in ignis einen neuen Schlüssel, ist der alte sofort ungültig. Trag den neuen dann auch hier ein.

### 4. In der server.cfg starten

ignisTab muss **nach** dem Framework und den anderen benötigten Ressourcen starten:

```cfg
ensure oxmysql
ensure qb-core          # oder: ensure es_extended
ensure ox_inventory     # nur wenn du es nutzt
ensure emergencydispatch  # nur für EMD-Sync
ensure ignisTab
```

Beim Start meldet ignisTab in der Konsole, wenn der API-Schlüssel noch `CHANGE_ME` ist.

### 5. Testen

Starte den Server neu, geh mit einem Charakter in den Job `ambulance` ins Spiel und öffne das Tablet mit `/enotf` oder F9. Es sollte die eNOTF-Seite deiner ignis-Installation laden. Das FireTab öffnest du mit `/firetab` (Job `fire`).

Bleibt das Tablet weiß, sieh unter [Hilfe bei Problemen](#hilfe-bei-problemen) nach.


## Einstellungen in der config.lua

### Tablets

`Config.eNOTF` und `Config.FireTab` sind gleich aufgebaut:

| Einstellung | Bedeutung | Standard |
|---|---|---|
| `Enabled` | Tablet ein- oder ausschalten | `true` |
| `Command` | Chatbefehl zum Öffnen | `enotf` / `firetab` |
| `OpenKey` | Standardtaste zum Öffnen, `nil` heißt keine Taste vorbelegt | `F9` / `nil` |
| `AllowedJobs` | Jobs, die das Tablet öffnen dürfen. Die Namen müssen genau so heißen wie in deinem Framework. | `ambulance`, `admin` / `fire`, `admin` |
| `RequireItem` | Tablet nur mit Gegenstand im Inventar | `false` |
| `RequiredItem` | Name des Gegenstands | `tablet` |
| `UseProp` | Tablet als Gegenstand in der Hand zeigen | `true` |

Die Taste kann jeder Spieler unter **Einstellungen › Tastenbelegung › FiveM** selbst ändern. Geschlossen wird das Tablet mit ESC oder dem Kreuz.

Brauchst du `RequireItem`, musst du den Gegenstand selbst in deinem Inventar anlegen. ignisTab bringt keinen mit.

### Tablet-Login

Die Anmeldung mit Discord funktioniert im Spielbrowser nicht. Mit dem Tablet-Login holt sich der Server für die Discord-ID des Spielers einen einmaligen Anmeldelink von ignis, und der Spieler ist im Tablet direkt angemeldet.

So schaltest du ihn ein:

1. In ignis unter **Einstellungen › System-Konfiguration › Funktionen** die Option **Anmeldung über ignisTab** einschalten.
2. In der `config.lua`:

   ```lua
   Config.TabletLogin = { Enabled = true }
   ```

3. Sicherstellen, dass FiveM eine Discord-ID für jeden Spieler kennt (siehe unten).

Damit das klappt, muss die **System-URL** in ignis (Einstellungen › System-Konfiguration › Adresse und Anmeldung) dieselbe Adresse sein wie `Config.BaseURL`. Sonst landet die Anmeldung auf einer anderen Adresse als die Tablet-Seiten.

Wer kein ignis-Konto mit dieser Discord-ID hat, sieht weiter die normale Anmeldeseite. Neue Konten legt der Tablet-Login nicht an. Ein Login gilt für beide Tablets.

**Discord-ID im Spiel:** FiveM kennt die Discord-ID nur, wenn der Spieler Discord auf seinem PC geöffnet hat, während er sich verbindet. Willst du das zur Pflicht machen, weise Spieler ohne Discord beim Verbinden ab, zum Beispiel mit einer kleinen Server-Ressource:

```lua
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    if not GetPlayerIdentifierByType(source, 'discord') then
        setKickReason('Bitte starte Discord, bevor du dich verbindest.')
        CancelEvent()
    end
end)
```

### EMD-Sync

Gleicht Fahrzeuge, Status, Einsatzdaten und Lagemeldungen zwischen dem Einsatzleitsystem `emergencydispatch` und ignis ab. Braucht `emergencydispatch` und `oxmysql`.

```lua
Config.EMDSync = {
    Enabled = true,
    HeartbeatInterval = 5000,
    -- ...
}
```

Die Standardwerte passen für die meisten Server: Status alle 5 Sekunden, Einsatzdaten und Lagemeldungen alle 30 Sekunden. Mit `/emdsync` stößt du einen Abgleich von Hand an, dafür braucht dein Konto das Recht `command.emdsync`.

### eNOTF-Abrechnung

Holt freigegebene eNOTF-Protokolle aus ignis, damit ein Abrechnungsskript auf deinem Server Rechnungen stellen kann. Braucht ignis ab 2026.0.26-beta und `oxmysql`.

```lua
Config.ENOTFBilling = {
    Enabled = true,
    AutoSync = true,        -- im Hintergrund abrufen
    SyncInterval = 900000,  -- alle 15 Minuten
    FilterProcessed = true  -- schon abgerechnete Protokolle überspringen
}
```

Mit `FilterProcessed` legt ignisTab beim ersten Start die Tabelle `enotf_billing` selbst an. Was pro Protokoll passieren soll (Rechnung stellen, Geld abbuchen), trägst du in `server/billing-custom.lua` bei `processBilling` ein. Dort steht ein Beispiel.

Mit `/enotf-billing-sync` stößt du einen Abruf von Hand an.

### Rechte (ACE)

Für die Befehle und den Zugriff auf Patientendaten braucht es diese Rechte in der `server.cfg`:

```cfg
add_ace group.admin command.emdsync allow
add_ace group.admin command.enotf-billing-sync allow
add_ace group.admin ignistab.billing allow
```

`ignistab.billing` erlaubt einem Spieler, abrechnungsfertige Protokolle mit Patientendaten abzurufen. Gib es nur an Gruppen, die das wirklich brauchen.


## Was in ignis eingestellt sein muss

| In ignis | Wofür |
|---|---|
| HTTPS mit gültigem Zertifikat | alles |
| Plugin eNOTF und fireTab eingeschaltet | die beiden Tablets |
| API-Schlüssel (System-Konfiguration › Technik) | alles, was der Server mit ignis bespricht |
| Anmeldung über ignisTab (System-Konfiguration › Funktionen) | Tablet-Login |
| System-URL gleich `Config.BaseURL` | Tablet-Login |
| Bei nginx die `map`-Blöcke für FiveM aus `nginx.conf.example` | sonst bleibt das Tablet weiß |

Ob man sich im Tablet bei ignis anmelden muss, legt jeweils die Option **Nur mit ignis-Konto** in den Abschnitten eNOTF und fireTab der System-Konfiguration fest. Ab Werk sind beide aus, die Tablets funktionieren dann auch ohne Anmeldung.


## Updates

Lade die neue ZIP-Datei herunter und ersetze den Ordner `resources/ignisTab`. Sichere vorher deine `config.lua` und `config_server.lua` und übernimm deine Werte danach in die neuen Dateien, denn manchmal kommen Einstellungen dazu. Vergleich dafür am besten beide Fassungen. Danach `restart ignisTab` oder den Server neu starten.


## Hilfe bei Problemen

**Das Tablet bleibt weiß:**

- Stimmt `Config.BaseURL`, mit `https://` und `/` am Ende?
- Läuft ignis über HTTPS mit gültigem Zertifikat? Öffne die Adresse zum Test im normalen Browser.
- Bei nginx: Sind die `map`-Blöcke für FiveM eingebunden? Ohne sie verbietet nginx das Einbetten ins Tablet.

**„Fehler beim Abrufen deiner Daten!“:** ignisTab hat kein QBCore oder ESX gefunden. Prüf, ob das Framework vor ignisTab startet, oder setz `Config.Framework` fest auf `'qbcore'` oder `'esx'`.

**„Du darfst dieses Tablet nicht nutzen!“:** Der Job des Charakters steht nicht in `AllowedJobs`. Achte auf die genaue Schreibweise aus deinem Framework.

**Konsole meldet „API key rejected“ oder ignis antwortet mit 403:** Der Schlüssel in `config_server.lua` stimmt nicht mit dem in ignis überein. Kopier ihn neu.

**ignis antwortet mit 503:** In ignis ist noch kein API-Schlüssel gesetzt.

**Tablet-Login klappt nicht:**

- Ist in ignis **Anmeldung über ignisTab** eingeschaltet?
- Hat der Spieler beim Verbinden Discord geöffnet?
- Hat sein ignis-Konto diese Discord-ID? Gehört die Discord-ID zu mehreren Konten, lehnt ignis die Anmeldung ab, der Spieler bekommt dann einen Hinweis.
- Stimmt die System-URL in ignis mit `Config.BaseURL` überein?

**Mehr Ausgaben:** `Config.Debug = true` schreibt ausführliche Meldungen in die Server- und F8-Konsole.

Fragen und Fehlermeldungen gerne als Issue unter <https://github.com/EmergencyForge/ignisTab/issues>.
