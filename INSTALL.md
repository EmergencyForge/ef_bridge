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

ef_bridge hat keine config-Dateien. Alles stellst du im Spiel im Admin-Panel (`/efbridge`) oder in der Serverkonsole mit `efbridge` ein, der Server speichert es selbst.

### 1. Herunterladen und entpacken

Lade auf der [Release-Seite](https://github.com/EmergencyForge/ef_bridge/releases) die neueste ZIP-Datei herunter und entpack sie in den `resources`-Ordner deines Servers. Danach gibt es einen Ordner `resources/ef_bridge`.

Behalte den Ordnernamen `ef_bridge` bei. Andere Skripte sprechen die Ressource über `exports['ef_bridge']` an, und der Server legt die Einstellungen unter diesem Namen ab.

### 2. In der server.cfg starten

ef_bridge muss **nach** dem Framework und den anderen benötigten Ressourcen starten:

```cfg
ensure oxmysql
ensure qb-core            # oder: ensure qbx_core / ensure es_extended
ensure ox_inventory       # nur wenn du es nutzt
ensure emergencydispatch  # nur für EMD-Sync
ensure ef_bridge

add_ace group.admin ef_bridge.admin allow
```

### 3. Einrichten

Ab Werk ist alles aus. Im Spiel öffnest du als Admin mit `/efbridge` das Panel und trägst ein, was du nutzt:

- **ignis:** Adresse (mit `https://` und `/` am Ende, liegt ignis in einem Unterordner, gehört er dazu) und API-Schlüssel. Den Schlüssel findest du in ignis unter **Einstellungen › System-Konfiguration › Technik › API-Schlüssel**.
- **eNOTF-Tablet / FireTab:** „Tablet aktiv“ einschalten, die erlaubten Jobs prüfen.
- **EMD-Sync, eNOTF-Abrechnung, Lex:** einschalten, wenn du sie nutzt, siehe unten.

Speichern, fertig. Unter **Status** prüft „Verbindung testen“ Adresse und Schlüssel von ignis und Lex.

Ist noch niemand auf dem Server, geht dasselbe in der Serverkonsole (txAdmin oder Terminal):

```
efbridge set Ignis.BaseURL https://ignis.example.de/
efbridge key ignis dein-schluessel-aus-ignis
efbridge set Tablets.eNOTF.Enabled on
efbridge set Tablets.FireTab.Enabled on
efbridge test
```

Kommst du von ignisTab, leg deine alten config-Dateien in den Ordner, siehe [Umstieg von ignisTab](#umstieg-von-ignistab).

### 4. Testen

Geh mit einem Charakter im Job `ambulance` ins Spiel und öffne das Tablet mit `/enotf` oder F9. Es sollte die eNOTF-Seite deiner ignis-Installation laden. Das FireTab öffnest du mit `/firetab` (Job `fire`).

Bleibt das Tablet weiß, sieh unter [Hilfe bei Problemen](#hilfe-bei-problemen) nach.


## Admin-Panel

`/efbridge` öffnet das Panel mit dem Zustand aller Module und allen Einstellungen. Dafür braucht das Konto das Recht `ef_bridge.admin`. Der Server prüft das bei jedem Öffnen, Speichern und Knopfdruck neu.

- Änderungen gelten sofort. Ausnahmen sind mit „nach Neustart“ markiert: Chatbefehle, Standardtasten, das Framework und die Statustabelle von EMD-Sync. Die gelten nach `restart ef_bridge`.
- Der Server speichert alles in seinem KVP-Speicher. Es bleibt über Neustarts und Updates erhalten, auch wenn du den Ordner ersetzt. „Auf Standard zurücksetzen“ nimmt eine Änderung zurück.
- API-Schlüssel lassen sich eintragen und löschen, aber nie wieder anzeigen, auch nicht für Admins. Sie verlassen den Server nicht.
- Werte, die nur der Server braucht (EMD-Sync, Abrechnung, Lex), gehen nur an Admins, die das Panel öffnen. Die übrigen bekommen alle Spieler, weil die Tablets sie brauchen.
- Prop-Position und Animation der Tablets stehen pro Bereich unter „Erweitert“.

In der Serverkonsole geht alles auch ohne Panel:

| Befehl | Wirkung |
|---|---|
| `efbridge status` | Version, Framework, Datenbank, welche Schlüssel gesetzt sind, letzter Lex-Abgleich |
| `efbridge list [Bereich]` | alle Einstellungen mit Wert, etwa `efbridge list lex` |
| `efbridge get <Einstellung>` | ein Wert, zum Beispiel `efbridge get Lex.BatchSize` |
| `efbridge set <Einstellung> <Wert>` | ändern; Listen mit Komma, Schalter mit `on`/`off` |
| `efbridge reset <Einstellung>` | zurück auf den Standard |
| `efbridge key <ignis\|lex> <Schlüssel>` | API-Schlüssel setzen, `clear` löscht ihn |
| `efbridge import` | config-Dateien oder einen Export aus dem Ordner übernehmen |
| `efbridge export` | geänderte Einstellungen ohne Schlüssel nach `settings-export.json` |
| `efbridge lexsync` | vollständiger Abgleich mit Lex |
| `efbridge test` | Verbindung zu ignis und Lex prüfen |

Mit `export` und `import` ziehst du Einstellungen auf einen anderen Server um. Die Schlüssel trägst du dort neu ein.


## Einstellungen

Die Namen sind die, die `efbridge get/set` versteht. Im Panel stehen sie in den Bereichen mit deutscher Beschriftung.

### Tablets

`Tablets.eNOTF.*` und `Tablets.FireTab.*` sind gleich aufgebaut:

| Einstellung | Bedeutung | Standard |
|---|---|---|
| `Enabled` | Tablet ein- oder ausschalten | aus |
| `AllowedJobs` | Jobs, die das Tablet öffnen dürfen. Die Namen müssen genau so heißen wie in deinem Framework. | `ambulance`, `admin` / `fire`, `admin` |
| `RequireItem` | Tablet nur mit Gegenstand im Inventar | aus |
| `RequiredItem` | Name des Gegenstands | `tablet` |
| `UseProp` | Tablet als Gegenstand in der Hand zeigen | an |
| `Path` | Seite in ignis, die das Tablet öffnet | `enotf/overview.php` / `einsatz/list.php` |
| `Command` | Chatbefehl zum Öffnen (nach Neustart) | `enotf` / `firetab` |
| `OpenKey` | Standardtaste, leer heißt keine Taste vorbelegt (nach Neustart) | `F9` / leer |

Die Taste kann jeder Spieler unter **Einstellungen › Tastenbelegung › FiveM** selbst ändern. Geschlossen wird das Tablet mit ESC oder dem Kreuz.

Brauchst du `RequireItem`, musst du den Gegenstand selbst in deinem Inventar anlegen. ef_bridge bringt keinen mit.

### Tablet-Login

Die Anmeldung mit Discord funktioniert im Spielbrowser nicht. Mit dem Tablet-Login holt sich der Server für die Discord-ID des Spielers einen einmaligen Anmeldelink von ignis, und der Spieler ist im Tablet direkt angemeldet.

So schaltest du ihn ein:

1. In ignis unter **Einstellungen › System-Konfiguration › Funktionen** die Option **Anmeldung über ef_bridge** einschalten (in älteren ignis-Versionen „Anmeldung über ignisTab“).
2. Im Panel unter ignis „Tablet-Login über Discord-ID“ einschalten (`Ignis.TabletLogin`).
3. Sicherstellen, dass FiveM eine Discord-ID für jeden Spieler kennt (siehe unten).

Damit das klappt, muss die **System-URL** in ignis (Einstellungen › System-Konfiguration › Adresse und Anmeldung) dieselbe Adresse sein wie `Ignis.BaseURL`. Sonst landet die Anmeldung auf einer anderen Adresse als die Tablet-Seiten.

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

Gleicht Fahrzeuge, Status, Einsatzdaten und Lagemeldungen zwischen dem Einsatzleitsystem `emergencydispatch` und ignis ab. Braucht `emergencydispatch`, `oxmysql`, die ignis-Adresse und den Schlüssel. Einschalten mit `EMDSync.Enabled`.

Die Standardwerte passen für die meisten Server: Status alle 5 Sekunden, Einsatzdaten und Lagemeldungen alle 30 Sekunden. Mit `/emdsync` stößt du einen Abgleich von Hand an, dafür braucht dein Konto das Recht `command.emdsync`.

### eNOTF-Abrechnung

Holt freigegebene eNOTF-Protokolle aus ignis, damit ein Abrechnungsskript auf deinem Server Rechnungen stellen kann. Braucht ignis ab 2026.0.26-beta und `oxmysql`. Einschalten mit `ENOTFBilling.Enabled`, im Hintergrund abrufen mit `ENOTFBilling.AutoSync` (alle 15 Minuten, `ENOTFBilling.SyncInterval`).

Mit „Schon abgerechnete Protokolle überspringen“ (`ENOTFBilling.FilterProcessed`, ab Werk an) legt ef_bridge die Tabelle `enotf_billing` selbst an. Was pro Protokoll passieren soll (Rechnung stellen, Geld abbuchen), trägst du in `server/billing-custom.lua` bei `processBilling` ein. Dort steht ein Beispiel. Das ist die einzige Datei, in der du noch selbst etwas schreibst, denn sie ist Code, keine Einstellung.

Mit `/enotf-billing-sync` stößt du einen Abruf von Hand an.

### Lex-Abgleich

Meldet Charaktere als Personen und ihre Fahrzeuge samt Halter an Lex. Braucht `oxmysql` und QBCore, Qbox oder ESX.

In Lex unter **Einstellungen › FiveM-Abgleich**:

1. „Abgleich mit dem Spielserver zulassen“ anhaken und speichern.
2. „Schlüssel erzeugen“. Lex zeigt den Schlüssel genau einmal, kopier ihn gleich.
3. Die Adresse unter „Adresse für ef_bridge“ abschreiben.

Im ef_bridge-Panel unter Lex „Abgleich mit Lex aktiv“ einschalten, Adresse und Schlüssel eintragen, speichern. Oder in der Konsole:

```
efbridge set Lex.BaseURL https://lex.example.de/
efbridge key lex lex_…
efbridge set Lex.Enabled on
efbridge test
```

Was dabei passiert:

- Ein Charakter, der sich einloggt, geht nach ein paar Sekunden mit seinen Fahrzeugen an Lex. Loggen sich viele gleichzeitig ein, gehen sie gesammelt in wenigen Anfragen raus.
- Der vollständige Abgleich liest alle Charaktere und Fahrzeuge aus der Framework-Datenbank (QBCore/Qbox: `players`, `player_vehicles`; ESX: `users`, `owned_vehicles`) und schickt sie in Paketen. Er läuft eine Minute nach dem Start und dann alle sechs Stunden (`Lex.FullSync.IntervalMinutes`), von Hand mit `efbridge lexsync` oder im Panel.
- Lex erkennt Personen an der Citizen-ID bzw. dem ESX-Identifier. Eine in Lex von Hand angelegte Person mit gleichem Vor- und Nachnamen und gleichem Geburtsdatum wird verknüpft statt doppelt angelegt.
- Was das Spiel meldet, gilt: Name, Geburtsdatum, Geschlecht und Telefon, beim Fahrzeug Kennzeichen, Modell, Klasse und Halter. Adresse, Foto, Notizen, Akten und Vorgänge in Lex bleiben unberührt. In Lex gelöschte Personen und Fahrzeuge holt der Abgleich nicht zurück, Kennzeichen des Fuhrparks fasst er nicht an.
- Mit „Verschwundene Fahrzeuge abmelden“ (ab Werk an) meldet Lex Spielfahrzeuge ab, die der vollständige Abgleich nicht mehr findet (verkauft, gelöscht). Taucht so ein Fahrzeug wieder auf, ist es wieder zugelassen.
- Die Fahrzeugfarbe übernimmt ef_bridge nicht, die Frameworks speichern nur eine Farbnummer. Sie bleibt in Lex von Hand pflegbar.

Was Lex übersprungen hat und warum, steht nach jedem Abgleich in der Serverkonsole, mit `efbridge set Debug on` auch pro Datensatz.

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

`ef_bridge.admin` öffnet das Panel und erlaubt damit auch, API-Schlüssel zu setzen. `ef_bridge.billing` erlaubt einem Spieler, abrechnungsfertige Protokolle mit Patientendaten abzurufen. Gib beide nur an Gruppen, die das wirklich brauchen. Das alte Recht `ignistab.billing` gilt weiter.


## Was in ignis eingestellt sein muss

| In ignis | Wofür |
|---|---|
| HTTPS mit gültigem Zertifikat | alles |
| Plugin eNOTF und fireTab eingeschaltet | die beiden Tablets |
| API-Schlüssel (System-Konfiguration › Technik) | alles, was der Server mit ignis bespricht |
| Anmeldung über ef_bridge (System-Konfiguration › Funktionen) | Tablet-Login |
| System-URL gleich der ignis-Adresse in ef_bridge | Tablet-Login |
| Bei nginx die `map`-Blöcke für FiveM aus `nginx.conf.example` | sonst bleibt das Tablet weiß |

Ob man sich im Tablet bei ignis anmelden muss, legt jeweils die Option **Nur mit ignis-Konto** in den Abschnitten eNOTF und fireTab der System-Konfiguration fest. Ab Werk sind beide aus, die Tablets funktionieren dann auch ohne Anmeldung.


## Umstieg von ignisTab

ef_bridge ist ignisTab unter neuem Namen, ohne config-Dateien und mit dem Lex-Abgleich.

1. `ensure ignisTab` in der `server.cfg` durch `ensure ef_bridge` ersetzen und `add_ace group.admin ef_bridge.admin allow` ergänzen.
2. `config.lua` und `config_server.lua` aus dem alten Ordner `resources/ignisTab` in den neuen Ordner `resources/ef_bridge` kopieren, dann den alten Ordner löschen.
3. Server starten. Beim ersten Start übernimmt ef_bridge die Werte aus beiden Dateien, Schlüssel eingeschlossen, und schreibt in die Konsole, was es übernommen hat und was nicht (etwa einen ungültigen Wert). Danach liest es die Dateien nicht mehr. Prüf das Ergebnis mit `/efbridge` und lösch die Dateien.
4. Skripte, die `exports['ignisTab']` oder `exports.ignisTab` aufrufen (etwa für `getReleasedENOTFProtocols` oder `syncHeartbeat`), auf `exports['ef_bridge']` umstellen. Die Namen der Exporte und die Events `enotf-billing:*` und `emd:*` sind gleich geblieben.
5. `ignistab.billing` kannst du in `ef_bridge.billing` umbenennen, das alte Recht gilt aber weiter. Der Testbefehl `/ignistabtest` heißt jetzt `/efbridgetest`.

Hast du ef_bridge schon eingerichtet und willst trotzdem alte Dateien übernehmen, leg sie in den Ordner und ruf `efbridge import` auf. Im Panel unter **Import** geht es auch ohne Dateien: Inhalt einfügen, Vorschau ansehen, übernehmen.

Die Dateien liest ef_bridge in einer abgeschotteten Umgebung, ohne Zugriff auf Natives, andere Ressourcen oder Dateien. Sie stehen nicht im Manifest, Spieler bekommen sie also nie.

Hattest du den API-Schlüssel früher in der `config.lua` (ganz alte Versionen), war er für jeden Spieler lesbar. Erzeug in ignis einen neuen und trag ihn mit `efbridge key ignis <Schlüssel>` ein.


## Updates

Lade die neue ZIP-Datei herunter und ersetze den Ordner `resources/ef_bridge`, danach `restart ef_bridge` oder den Server neu starten. Die Einstellungen liegen beim Server und bleiben erhalten. Nur `server/billing-custom.lua` solltest du vorher sichern, wenn du dort eigenen Code hast.


## Hilfe bei Problemen

**Das Tablet bleibt weiß:**

- Stimmt die Adresse von ignis (`efbridge get Ignis.BaseURL`), mit `https://` und `/` am Ende?
- Läuft ignis über HTTPS mit gültigem Zertifikat? Öffne die Adresse zum Test im normalen Browser.
- Bei nginx: Sind die `map`-Blöcke für FiveM eingebunden? Ohne sie verbietet nginx das Einbetten ins Tablet.

**„Fehler beim Abrufen deiner Daten!“:** ef_bridge hat kein QBCore, Qbox oder ESX gefunden. Prüf, ob das Framework vor ef_bridge startet, oder setz es fest: `efbridge set Framework qbcore` (oder `esx`) und `restart ef_bridge`.

**„Für das Tablet fehlt die Adresse von ignis“:** Unter ignis im Panel die Adresse eintragen.

**„Die Einstellungen werden noch geladen“:** Der Client hat vom Server noch keine Einstellungen bekommen, meist direkt nach dem Verbinden oder einem Neustart der Ressource. Ein paar Sekunden warten.

**„Du darfst dieses Tablet nicht nutzen!“:** Der Job des Charakters steht nicht in `AllowedJobs`. Achte auf die genaue Schreibweise aus deinem Framework.

**„Für das ef_bridge-Panel fehlt dir das Recht.“:** Dem Konto fehlt `ef_bridge.admin`. Prüf die `add_ace`-Zeile und ob der Spieler in der Gruppe ist (`add_principal identifier.fivem:… group.admin`).

**Konsole meldet „API key rejected“ oder ignis antwortet mit 403:** Der Schlüssel in ef_bridge stimmt nicht mit dem in ignis überein. Kopier ihn neu und trag ihn im Panel oder mit `efbridge key ignis <Schlüssel>` ein.

**ignis antwortet mit 503:** In ignis ist noch kein API-Schlüssel gesetzt.

**Lex-Abgleich klappt nicht:** `efbridge test` sagt, woran es liegt:

- „kein Schlüssel erzeugt“: in Lex unter Einstellungen › FiveM-Abgleich einen erzeugen.
- „lehnt den Schlüssel ab“: Der Schlüssel stimmt nicht. Lex zeigt einen Schlüssel nur einmal; im Zweifel einen neuen erzeugen und mit `efbridge key lex <Schlüssel>` eintragen.
- „ausgeschaltet“: in Lex den Haken bei „Abgleich mit dem Spielserver zulassen“ setzen.
- „nicht erreichbar“: Adresse prüfen, und ob der FiveM-Server Lex über HTTPS erreicht.

**Tablet-Login klappt nicht:**

- Ist in ignis **Anmeldung über ef_bridge** eingeschaltet?
- Hat der Spieler beim Verbinden Discord geöffnet?
- Hat sein ignis-Konto diese Discord-ID? Gehört die Discord-ID zu mehreren Konten, lehnt ignis die Anmeldung ab, der Spieler bekommt dann einen Hinweis.
- Stimmt die System-URL in ignis mit der Adresse in ef_bridge (`Ignis.BaseURL`) überein?

**Mehr Ausgaben:** `efbridge set Debug on` schreibt ausführliche Meldungen in die Server- und F8-Konsole.

Fragen und Fehlermeldungen gerne als Issue unter <https://github.com/EmergencyForge/ef_bridge/issues>.
