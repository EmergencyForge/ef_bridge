# ef_bridge installieren

ef_bridge verbindet deinen FiveM-Server mit ignis und Lex. Für ignis bringt es das eNOTF-Tablet für den Rettungsdienst und das FireTab für die Feuerwehr ins Spiel, auf Wunsch auch den Abgleich mit dem Einsatzleitsystem (EMD-Sync) und die Abrechnung freigegebener eNOTF-Protokolle. Für Lex meldet es Charaktere als Personen und ihre Fahrzeuge samt Halter.

ef_bridge ist nur die Brücke ins Spiel. Für die ignis-Module brauchst du eine laufende ignis-Installation (Anleitung im [ignis-Repository](https://github.com/EmergencyForge/ignis/blob/main/INSTALL.md)), für den Lex-Abgleich eine Lex-Installation.

Kommst du von ignisTab, lies zuerst [Umstieg von ignisTab](#umstieg-von-ignistab).


## Was du brauchst

**Auf dem FiveM-Server**

- ein aktuelles FiveM-Server-Build (Artifacts)
- QBCore, Qbox oder ESX. Ohne Framework lässt sich kein Tablet öffnen und es gibt nichts für Lex, weil ef_bridge Name, Job und Charakter von dort holt.
- `oxmysql` für EMD-Sync, die eNOTF-Abrechnung und den Lex-Abgleich
- `emergencydispatch`, wenn du EMD-Sync nutzt
- `ox_inventory`, wenn ein Tablet nur mit einem Gegenstand im Inventar funktionieren soll (optional, QBCore- und ESX-Inventare gehen auch)

**Bei ignis**

- ignis ab Version 2026.0.14-beta, für die eNOTF-Abrechnung ab 2026.0.26-beta
- ignis muss über **HTTPS mit gültigem Zertifikat** erreichbar sein, für die Spieler und vom FiveM-Server aus. ef_bridge baut alle Adressen mit `https://` auf.
- das Plugin **eNOTF** ist eingeschaltet (für das eNOTF-Tablet), das Plugin **fireTab** ebenfalls (für das FireTab)

**Bei Lex**

- Lex mit dem FiveM-Abgleich (Einstellungen › FiveM-Abgleich), erreichbar über HTTPS vom FiveM-Server aus


## Installation

### 1. Herunterladen und entpacken

Lade auf der [Release-Seite](https://github.com/EmergencyForge/ignisTab/releases) die neueste ZIP-Datei herunter und entpack sie in den `resources`-Ordner deines Servers. Danach gibt es einen Ordner `resources/ef_bridge`.

Behalte den Ordnernamen `ef_bridge` bei. Andere Skripte sprechen die Ressource über `exports['ef_bridge']` an, und der Server legt die Einstellungen aus dem Admin-Panel unter diesem Namen ab.

### 2. Adresse von ignis eintragen

Öffne `config.lua` und trag die Adresse deiner ignis-Installation ein, mit `/` am Ende:

```lua
Config.Ignis = {
    BaseURL = 'https://ignis.example.de/',
    TabletLogin = false
}
```

Liegt ignis in einem Unterordner, gehört er dazu, zum Beispiel `https://example.de/ignis/`. Nutzt du nur Lex, lass die Adresse stehen und schalte in `Config.Tablets` beide Tablets mit `Enabled = false` ab.

### 3. API-Schlüssel eintragen

Den ignis-Schlüssel findest du in ignis unter **Einstellungen › System-Konfiguration › Technik › API-Schlüssel**. Er wird bei der Installation von ignis erzeugt, mit dem Auge-Symbol blendest du ihn ein. Trag ihn in `config_server.lua` ein:

```lua
ServerConfig.Ignis = {
    APIKey = 'dein-schluessel-aus-ignis'
}
```

Für Lex siehe [Lex-Abgleich](#lex-abgleich).

> Schlüssel gehören **nur** in `config_server.lua`. Die `config.lua` lädt jeder Spieler mit der Ressource herunter, ein Schlüssel darin wäre für alle lesbar. Hast du ihn früher in der `config.lua` stehen gehabt, lösch ihn dort und erzeug in ignis einen neuen.

Erzeugst du in ignis einen neuen Schlüssel, ist der alte sofort ungültig. Trag den neuen dann auch hier ein.

### 4. In der server.cfg starten

ef_bridge muss **nach** dem Framework und den anderen benötigten Ressourcen starten:

```cfg
ensure oxmysql
ensure qb-core            # oder: ensure qbx_core / ensure es_extended
ensure ox_inventory       # nur wenn du es nutzt
ensure emergencydispatch  # nur für EMD-Sync
ensure ef_bridge

add_ace group.admin ef_bridge.admin allow
```

Beim Start meldet ef_bridge in der Konsole, wenn ein benötigter Schlüssel noch `CHANGE_ME` ist.

### 5. Testen

Starte den Server neu und öffne als Admin mit `/efbridge` das Panel. Unter **Status** testet „Verbindung testen“ die Adresse und den Schlüssel von ignis und Lex.

Geh dann mit einem Charakter im Job `ambulance` ins Spiel und öffne das Tablet mit `/enotf` oder F9. Es sollte die eNOTF-Seite deiner ignis-Installation laden. Das FireTab öffnest du mit `/firetab` (Job `fire`).

Bleibt das Tablet weiß, sieh unter [Hilfe bei Problemen](#hilfe-bei-problemen) nach.


## Admin-Panel

`/efbridge` öffnet im Spiel ein Panel mit dem Zustand aller Module und fast allen Einstellungen aus beiden config-Dateien. Dafür braucht das Konto das Recht `ef_bridge.admin` (der Name steht in `Config.Admin.Ace`). Der Server prüft das bei jedem Öffnen, Speichern und Knopfdruck neu.

- Änderungen gelten sofort. Ausnahmen sind mit „nach Neustart“ markiert: Chatbefehle, Standardtasten, das Framework und die Statustabelle von EMD-Sync. Die gelten nach `restart ef_bridge`.
- Der Server speichert die Änderungen in seinem KVP-Speicher, nicht in den config-Dateien. Sie bleiben über Neustarts und Updates erhalten und gehen vor die Werte aus den Dateien. „Auf config-Datei zurücksetzen“ nimmt eine Änderung zurück.
- Die API-Schlüssel stehen nicht im Panel. Es zeigt nur, ob sie gesetzt sind.
- Werte, die nur der Server braucht (EMD-Sync, Abrechnung, Lex), gehen nur an Admins, die das Panel öffnen. Die übrigen bekommen alle Spieler, weil die Tablets sie brauchen.

Aus der Serverkonsole (txAdmin) geht dasselbe ohne Panel:

| Befehl | Wirkung |
|---|---|
| `efbridge status` | Version, Framework, Datenbank, welche Schlüssel gesetzt sind, letzter Lex-Abgleich |
| `efbridge get <Einstellung>` | aktueller Wert, zum Beispiel `efbridge get Lex.BatchSize` |
| `efbridge set <Einstellung> <Wert>` | ändern; Listen mit Komma, Schalter mit `on`/`off` |
| `efbridge reset <Einstellung>` | zurück auf den Wert aus der config-Datei |
| `efbridge lexsync` | vollständiger Abgleich mit Lex |
| `efbridge test` | Verbindung zu ignis und Lex prüfen |

Die Namen der Einstellungen sind die Pfade aus den config-Dateien ohne `Config.`/`ServerConfig.`, also `Tablets.eNOTF.AllowedJobs`, `EMDSync.Enabled`, `Lex.FullSync.IntervalMinutes`.


## Einstellungen in der config.lua

### Tablets

`Config.Tablets.eNOTF` und `Config.Tablets.FireTab` sind gleich aufgebaut:

| Einstellung | Bedeutung | Standard |
|---|---|---|
| `Enabled` | Tablet ein- oder ausschalten | `true` |
| `Command` | Chatbefehl zum Öffnen | `enotf` / `firetab` |
| `OpenKey` | Standardtaste zum Öffnen, `nil` heißt keine Taste vorbelegt | `F9` / `nil` |
| `Path` | Seite in ignis, die das Tablet öffnet | `enotf/overview.php` / `einsatz/list.php` |
| `AllowedJobs` | Jobs, die das Tablet öffnen dürfen. Die Namen müssen genau so heißen wie in deinem Framework. | `ambulance`, `admin` / `fire`, `admin` |
| `RequireItem` | Tablet nur mit Gegenstand im Inventar | `false` |
| `RequiredItem` | Name des Gegenstands | `tablet` |
| `UseProp` | Tablet als Gegenstand in der Hand zeigen | `true` |

Die Taste kann jeder Spieler unter **Einstellungen › Tastenbelegung › FiveM** selbst ändern. Geschlossen wird das Tablet mit ESC oder dem Kreuz.

Brauchst du `RequireItem`, musst du den Gegenstand selbst in deinem Inventar anlegen. ef_bridge bringt keinen mit.

### Tablet-Login

Die Anmeldung mit Discord funktioniert im Spielbrowser nicht. Mit dem Tablet-Login holt sich der Server für die Discord-ID des Spielers einen einmaligen Anmeldelink von ignis, und der Spieler ist im Tablet direkt angemeldet.

So schaltest du ihn ein:

1. In ignis unter **Einstellungen › System-Konfiguration › Funktionen** die Option **Anmeldung über ef_bridge** einschalten (in älteren ignis-Versionen „Anmeldung über ignisTab“).
2. In der `config.lua` `Config.Ignis.TabletLogin = true` setzen (oder im Panel unter ignis).
3. Sicherstellen, dass FiveM eine Discord-ID für jeden Spieler kennt (siehe unten).

Damit das klappt, muss die **System-URL** in ignis (Einstellungen › System-Konfiguration › Adresse und Anmeldung) dieselbe Adresse sein wie `Config.Ignis.BaseURL`. Sonst landet die Anmeldung auf einer anderen Adresse als die Tablet-Seiten.

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


## Einstellungen in der config_server.lua

### EMD-Sync

Gleicht Fahrzeuge, Status, Einsatzdaten und Lagemeldungen zwischen dem Einsatzleitsystem `emergencydispatch` und ignis ab. Braucht `emergencydispatch` und `oxmysql`.

```lua
ServerConfig.EMDSync = {
    Enabled = true,
    HeartbeatInterval = 5000,
    -- ...
}
```

Die Standardwerte passen für die meisten Server: Status alle 5 Sekunden, Einsatzdaten und Lagemeldungen alle 30 Sekunden. Mit `/emdsync` stößt du einen Abgleich von Hand an, dafür braucht dein Konto das Recht `command.emdsync`.

### eNOTF-Abrechnung

Holt freigegebene eNOTF-Protokolle aus ignis, damit ein Abrechnungsskript auf deinem Server Rechnungen stellen kann. Braucht ignis ab 2026.0.26-beta und `oxmysql`.

```lua
ServerConfig.ENOTFBilling = {
    Enabled = true,
    AutoSync = true,        -- im Hintergrund abrufen
    SyncInterval = 900000,  -- alle 15 Minuten
    FilterProcessed = true  -- schon abgerechnete Protokolle überspringen
}
```

Mit `FilterProcessed` legt ef_bridge die Tabelle `enotf_billing` selbst an. Was pro Protokoll passieren soll (Rechnung stellen, Geld abbuchen), trägst du in `server/billing-custom.lua` bei `processBilling` ein. Dort steht ein Beispiel.

Mit `/enotf-billing-sync` stößt du einen Abruf von Hand an.

### Lex-Abgleich

Meldet Charaktere als Personen und ihre Fahrzeuge samt Halter an Lex. Braucht `oxmysql` und QBCore, Qbox oder ESX.

In Lex unter **Einstellungen › FiveM-Abgleich**:

1. „Abgleich mit dem Spielserver zulassen“ anhaken und speichern.
2. „Schlüssel erzeugen“. Lex zeigt den Schlüssel genau einmal, kopier ihn gleich.
3. Die Adresse unter „Adresse für Config.Lex.BaseURL“ abschreiben.

In der `config_server.lua`:

```lua
ServerConfig.Lex = {
    Enabled = true,
    BaseURL = 'https://lex.example.de/',
    APIKey = 'lex_…',
    Persons = true,      -- Charaktere als Personen
    Vehicles = true,     -- eigene Fahrzeuge mit Halter
    SyncOnLogin = true,  -- wer sich einloggt, geht gleich an Lex
    FullSync = {
        OnStart = true,
        IntervalMinutes = 360,
        RetireMissingVehicles = true
    },
    BatchSize = 100
}
```

Was dabei passiert:

- Ein Charakter, der sich einloggt, geht nach ein paar Sekunden mit seinen Fahrzeugen an Lex. Loggen sich viele gleichzeitig ein, gehen sie gesammelt in wenigen Anfragen raus.
- Der vollständige Abgleich liest alle Charaktere und Fahrzeuge aus der Framework-Datenbank (QBCore/Qbox: `players`, `player_vehicles`; ESX: `users`, `owned_vehicles`) und schickt sie in Paketen. Er läuft eine Minute nach dem Start und dann alle `IntervalMinutes`, von Hand mit `efbridge lexsync` oder im Panel.
- Lex erkennt Personen an der Citizen-ID bzw. dem ESX-Identifier. Eine in Lex von Hand angelegte Person mit gleichem Vor- und Nachnamen und gleichem Geburtsdatum wird verknüpft statt doppelt angelegt.
- Was das Spiel meldet, gilt: Name, Geburtsdatum, Geschlecht und Telefon, beim Fahrzeug Kennzeichen, Modell, Klasse und Halter. Adresse, Foto, Notizen, Akten und Vorgänge in Lex bleiben unberührt. In Lex gelöschte Personen und Fahrzeuge holt der Abgleich nicht zurück, Kennzeichen des Fuhrparks fasst er nicht an.
- Mit `RetireMissingVehicles` meldet Lex Spielfahrzeuge ab, die der vollständige Abgleich nicht mehr findet (verkauft, gelöscht). Taucht so ein Fahrzeug wieder auf, ist es wieder zugelassen.
- Die Fahrzeugfarbe übernimmt ef_bridge nicht, die Frameworks speichern nur eine Farbnummer. Sie bleibt in Lex von Hand pflegbar.

Was Lex übersprungen hat und warum, steht nach jedem Abgleich in der Serverkonsole, mit `Config.Debug = true` auch pro Datensatz.

Andere Skripte können Änderungen sofort melden, etwa ein Autohaus nach dem Kauf:

```lua
exports.ef_bridge:LexSyncCharacter(source)   -- Spieler-Source, Citizen-ID oder ESX-Identifier
exports.ef_bridge:LexFullSync()              -- vollständiger Abgleich im Hintergrund
```

### Rechte (ACE)

```cfg
add_ace group.admin ef_bridge.admin allow
add_ace group.admin command.emdsync allow
add_ace group.admin command.enotf-billing-sync allow
add_ace group.admin ef_bridge.billing allow
```

`ef_bridge.admin` öffnet das Panel. `ef_bridge.billing` erlaubt einem Spieler, abrechnungsfertige Protokolle mit Patientendaten abzurufen. Gib beide nur an Gruppen, die das wirklich brauchen. Das alte Recht `ignistab.billing` gilt weiter.


## Was in ignis eingestellt sein muss

| In ignis | Wofür |
|---|---|
| HTTPS mit gültigem Zertifikat | alles |
| Plugin eNOTF und fireTab eingeschaltet | die beiden Tablets |
| API-Schlüssel (System-Konfiguration › Technik) | alles, was der Server mit ignis bespricht |
| Anmeldung über ef_bridge (System-Konfiguration › Funktionen) | Tablet-Login |
| System-URL gleich `Config.Ignis.BaseURL` | Tablet-Login |
| Bei nginx die `map`-Blöcke für FiveM aus `nginx.conf.example` | sonst bleibt das Tablet weiß |

Ob man sich im Tablet bei ignis anmelden muss, legt jeweils die Option **Nur mit ignis-Konto** in den Abschnitten eNOTF und fireTab der System-Konfiguration fest. Ab Werk sind beide aus, die Tablets funktionieren dann auch ohne Anmeldung.


## Umstieg von ignisTab

ef_bridge ist ignisTab unter neuem Namen, mit neu geordneter Konfiguration und dem Lex-Abgleich.

1. `ensure ignisTab` in der `server.cfg` durch `ensure ef_bridge` ersetzen und den alten Ordner `resources/ignisTab` löschen, nachdem du deine config-Dateien gesichert hast.
2. Die Werte in die neuen Dateien übernehmen:

   | ignisTab | ef_bridge |
   |---|---|
   | `Config.BaseURL` | `Config.Ignis.BaseURL` |
   | `Config.TabletLogin.Enabled` | `Config.Ignis.TabletLogin` |
   | `Config.eNOTF`, `Config.FireTab` | `Config.Tablets.eNOTF`, `Config.Tablets.FireTab` |
   | `Config.EMDSync` (config.lua) | `ServerConfig.EMDSync` (config_server.lua) |
   | `Config.ENOTFBilling` (config.lua) | `ServerConfig.ENOTFBilling` (config_server.lua) |
   | `ServerConfig.APIKey` | `ServerConfig.Ignis.APIKey` |

   Legst du die alten Dateien unverändert hinein, läuft ef_bridge trotzdem: es schiebt die Werte beim Start an die neuen Stellen und meldet in der Konsole jede Stelle, die du noch umziehen solltest.
3. Skripte, die `exports['ignisTab']` oder `exports.ignisTab` aufrufen (etwa für `getReleasedENOTFProtocols` oder `syncHeartbeat`), auf `exports['ef_bridge']` umstellen. Die Namen der Exporte und die Events `enotf-billing:*` und `emd:*` sind gleich geblieben.
4. `add_ace group.admin ef_bridge.admin allow` für das Panel ergänzen. `ignistab.billing` kannst du in `ef_bridge.billing` umbenennen, das alte Recht gilt aber weiter.
5. Der Testbefehl `/ignistabtest` heißt jetzt `/efbridgetest`.


## Updates

Lade die neue ZIP-Datei herunter und ersetze den Ordner `resources/ef_bridge`. Sichere vorher `config.lua` und `config_server.lua` und übernimm deine Werte danach in die neuen Dateien, denn manchmal kommen Einstellungen dazu. Vergleich dafür am besten beide Fassungen. Was du im Admin-Panel geändert hast, liegt beim Server und bleibt erhalten. Danach `restart ef_bridge` oder den Server neu starten.


## Hilfe bei Problemen

**Das Tablet bleibt weiß:**

- Stimmt `Config.Ignis.BaseURL`, mit `https://` und `/` am Ende? Im Panel kann eine Änderung den Wert aus der Datei überdecken, sieh unter ignis nach.
- Läuft ignis über HTTPS mit gültigem Zertifikat? Öffne die Adresse zum Test im normalen Browser.
- Bei nginx: Sind die `map`-Blöcke für FiveM eingebunden? Ohne sie verbietet nginx das Einbetten ins Tablet.

**„Fehler beim Abrufen deiner Daten!“:** ef_bridge hat kein QBCore, Qbox oder ESX gefunden. Prüf, ob das Framework vor ef_bridge startet, oder setz `Config.Framework` fest auf `'qbcore'` oder `'esx'`.

**„Du darfst dieses Tablet nicht nutzen!“:** Der Job des Charakters steht nicht in `AllowedJobs`. Achte auf die genaue Schreibweise aus deinem Framework.

**„Für das ef_bridge-Panel fehlt dir das Recht.“:** Dem Konto fehlt `ef_bridge.admin`. Prüf die `add_ace`-Zeile und ob der Spieler in der Gruppe ist (`add_principal identifier.fivem:… group.admin`).

**Konsole meldet „API key rejected“ oder ignis antwortet mit 403:** Der Schlüssel in `config_server.lua` stimmt nicht mit dem in ignis überein. Kopier ihn neu.

**ignis antwortet mit 503:** In ignis ist noch kein API-Schlüssel gesetzt.

**Lex-Abgleich klappt nicht:** `efbridge test` sagt, woran es liegt:

- „kein Schlüssel erzeugt“: in Lex unter Einstellungen › FiveM-Abgleich einen erzeugen.
- „lehnt den Schlüssel ab“: `ServerConfig.Lex.APIKey` stimmt nicht. Lex zeigt einen Schlüssel nur einmal; im Zweifel einen neuen erzeugen und eintragen.
- „ausgeschaltet“: in Lex den Haken bei „Abgleich mit dem Spielserver zulassen“ setzen.
- „nicht erreichbar“: Adresse prüfen, und ob der FiveM-Server Lex über HTTPS erreicht.

**Tablet-Login klappt nicht:**

- Ist in ignis **Anmeldung über ef_bridge** eingeschaltet?
- Hat der Spieler beim Verbinden Discord geöffnet?
- Hat sein ignis-Konto diese Discord-ID? Gehört die Discord-ID zu mehreren Konten, lehnt ignis die Anmeldung ab, der Spieler bekommt dann einen Hinweis.
- Stimmt die System-URL in ignis mit `Config.Ignis.BaseURL` überein?

**Mehr Ausgaben:** `Config.Debug = true` (oder `efbridge set Debug on`) schreibt ausführliche Meldungen in die Server- und F8-Konsole.

Fragen und Fehlermeldungen gerne als Issue unter <https://github.com/EmergencyForge/ignisTab/issues>.
