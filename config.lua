Config = {}

-- Framework-Erkennung (erkennt automatisch QBCore oder ESX)
Config.Framework = 'auto' -- 'auto', 'qbcore', oder 'esx'

-- ========================================
-- ZENTRALE URL & API KONFIGURATION
-- ========================================
-- Basis-URL deiner intraRP Installation
-- Beispiele:
--   https://deine-url.de/
--   https://deine-url.de/intrarp/
Config.BaseURL = 'https://deine-url.de/'  -- WICHTIG: mit / am Ende

-- Zentral definierter API-Key (für alle Systeme)
Config.APIKey = 'CHANGE_ME'  -- Setze hier deinen API-Key

-- Debug mode
Config.Debug = false

-- ========================================
-- ENOTF-TABLET KONFIGURATION
-- ========================================
Config.eNOTF = {
    Enabled = true,
    Command = 'enotf',
    OpenKey = 'F9',  -- Standardtaste (oder nil = keine Vorgabe, Spieler kann selbst zuweisen)
    AllowedJobs = {
        'ambulance',
        'admin'
    },
    RequireItem = false,
    RequiredItem = "tablet",
    UseProp = true,
    Prop = {
        model = "notfpad",
        bone = 18905,
        offset = {
            x = 0.1240,
            y = 0.0550,
            z = 0.1550,
            xRot = -76.0,
            yRot = -186.0,
            zRot = 58.3
        }
    }
}

-- ========================================
-- FIRETAB-TABLET KONFIGURATION
-- ========================================
Config.FireTab = {
    Enabled = true,
    Command = 'firetab',
    OpenKey = nil,  -- Standardtaste (oder nil = keine Vorgabe, Spieler kann selbst zuweisen)
    AllowedJobs = {
        'fire',
        'admin'
    },
    RequireItem = false,
    RequiredItem = "tablet",
    UseProp = true,
    Prop = {
        model = "firetab",
        bone = 18905,
        offset = {
            x = 0.1240,
            y = 0.0450,
            z = 0.1550,
            xRot = 18.0,
            yRot = -186.0,
            zRot = 58.3
        }
    }
}

-- ========================================
-- EMD-SYNCHRONISIERUNG EINSTELLUNGEN
-- ========================================
Config.EMDSync = {
    Enabled = false,  -- Auf true setzen, um die EMD-Synchronisierung zu aktivieren
    HeartbeatInterval = 5000,  -- Basis-Takt in Millisekunden (Standard: 5000 = 5 Sekunden)

    -- Dispatch-Daten Synchronisierung (Fahrzeuge, Einsatzdaten, Patienten)
    DispatchSync = {
        Enabled = true,  -- Auf true setzen, um Fahrzeug-/Einsatzdaten zu synchronisieren
        TickMultiplier = 6  -- Alle 6 Ticks = alle 30s (bei HeartbeatInterval = 5000)
    },

    -- Echtzeit Status-Synchronisierung (bidirektional: FiveM <-> Web)
    StatusSync = {
        Enabled = true,  -- Auf true setzen, um die Echtzeit-Status-Synchronisierung zu aktivieren
        SyncStatuses = {'C', '1', '2', '3', '4', '7', '8'},  -- Zu synchronisierende Status
        SourceTable = 'emd_dispatchlog',  -- Tabelle mit den Statusmeldungen
        TickMultiplier = 1  -- Jeden Tick = alle 5s (bei HeartbeatInterval = 5000)
    },

    -- Lagemeldung-Synchronisierung (Lagemeldungen pro Einsatz)
    LagemeldungSync = {
        Enabled = true,  -- Auf true setzen, um die Lagemeldung-Synchronisierung zu aktivieren
        TickMultiplier = 6  -- Alle 6 Ticks = alle 30s
    }
}

-- ========================================
-- eNOTF ABRECHNUNGSSYSTEM EINSTELLUNGEN
-- ========================================
Config.ENOTFBilling = {
    Enabled = false,  -- Auf true setzen, um das eNOTF-Abrechnungssystem zu aktivieren

    -- Automatische Synchronisierung
    AutoSync = false,  -- Automatisch im Hintergrund synchronisieren
    SyncInterval = 900000,  -- Synchronisations-Intervall in Millisekunden (Standard: 900000 = 15 Minuten)
    
    -- Filter für bereits verarbeitete Protokolle
    FilterProcessed = true,  -- Schließt bereits in FiveM-DB gespeicherte Protokolle aus (erfordert enotf_billing Tabelle)
    -- WICHTIG: Name + 123, Name + 123_1, Name + 123_2 = nur 1x abgerechnet (Basis-Nummer vor "_" ist entscheidend)
}

-- ========================================
-- TABLET ANIMATION EINSTELLUNGEN
-- ========================================
Config.Animation = {
    dict = "amb@world_human_seat_wall_tablet@female@base",
    anim = "base",
    flag = 50
}


--[[ DO NOT TOUCH ANYTHING BELOW THIS LINE OR YOU WILL BREAK THE SCRIPT // KEINE ÄNDERUNGEN UNTERHALB DIESER ZEILE VORNEHMEN, DA SONST DAS SKRIPT BESCHÄDIGT WIRD ]]--


Config.KeyControls = {
    -- Function Keys
    ['F1'] = 288,
    ['F2'] = 289,
    ['F3'] = 170,
    ['F4'] = 167,
    ['F5'] = 166,
    ['F6'] = 167,
    ['F7'] = 168,
    ['F8'] = 169,
    ['F9'] = 56,
    ['F10'] = 57,
    ['F11'] = 344,
    ['F12'] = 199,
    
    -- Number Keys
    ['1'] = 157,
    ['2'] = 158,
    ['3'] = 160,
    ['4'] = 164,
    ['5'] = 165,
    ['6'] = 159,
    ['7'] = 161,
    ['8'] = 162,
    ['9'] = 163,
    ['0'] = 84,
    
    -- Letter Keys
    ['A'] = 34,
    ['B'] = 29,
    ['C'] = 26,
    ['D'] = 9,
    ['E'] = 38,
    ['F'] = 23,
    ['G'] = 47,
    ['H'] = 74,
    ['I'] = 73,
    ['J'] = 311,
    ['K'] = 311,
    ['L'] = 182,
    ['M'] = 244,
    ['N'] = 249,
    ['O'] = 19,
    ['P'] = 199,
    ['Q'] = 44,
    ['R'] = 45,
    ['S'] = 8,
    ['T'] = 245,
    ['U'] = 303,
    ['V'] = 0,
    ['W'] = 32,
    ['X'] = 73,
    ['Y'] = 246,
    ['Z'] = 20,
    
    -- Arrow Keys
    ['UP'] = 172,
    ['DOWN'] = 173,
    ['LEFT'] = 174,
    ['RIGHT'] = 175,
    
    -- Special Keys
    ['SPACE'] = 22,
    ['ENTER'] = 18,
    ['ESC'] = 322,
    ['BACKSPACE'] = 194,
    ['DELETE'] = 178,
    ['TAB'] = 37,
    ['CAPSLOCK'] = 137,
    ['SHIFT'] = 21,
    ['CTRL'] = 36,
    ['ALT'] = 19,
    
    -- Numpad Keys
    ['NUMPAD0'] = 96,
    ['NUMPAD1'] = 97,
    ['NUMPAD2'] = 98,
    ['NUMPAD3'] = 99,
    ['NUMPAD4'] = 100,
    ['NUMPAD5'] = 101,
    ['NUMPAD6'] = 102,
    ['NUMPAD7'] = 103,
    ['NUMPAD8'] = 104,
    ['NUMPAD9'] = 105,
    ['NUMPADENTER'] = 201,
    ['NUMPADPLUS'] = 96,
    ['NUMPADMINUS'] = 97,
    ['NUMPADMULTIPLY'] = 100,
    ['NUMPADDIVIDE'] = 99,
    ['NUMPADDECIMAL'] = 107,
    
    -- Punctuation and Symbols
    ['MINUS'] = 84,
    ['EQUALS'] = 83,
    ['LEFTBRACKET'] = 39,
    ['RIGHTBRACKET'] = 40,
    ['BACKSLASH'] = 43,
    ['SEMICOLON'] = 51,
    ['QUOTE'] = 52,
    ['COMMA'] = 82,
    ['PERIOD'] = 81,
    ['SLASH'] = 80,
    ['GRAVE'] = 243,
    
    -- Mouse Buttons
    ['MOUSE1'] = 24,  -- Left Click
    ['MOUSE2'] = 25,  -- Right Click
    ['MOUSE3'] = 348, -- Middle Click
    ['MOUSE4'] = 349, -- Mouse Button 4
    ['MOUSE5'] = 350, -- Mouse Button 5
    ['SCROLLUP'] = 241,
    ['SCROLLDOWN'] = 242,
    
    -- Additional Special Keys
    ['HOME'] = 213,
    ['END'] = 214,
    ['PAGEUP'] = 10,
    ['PAGEDOWN'] = 11,
    ['INSERT'] = 121,
    ['PRINTSCREEN'] = 199,
    ['SCROLLLOCK'] = 145,
    ['PAUSE'] = 199,
    
    -- Media Keys
    ['VOLUMEUP'] = 96,
    ['VOLUMEDOWN'] = 97,
    ['MUTE'] = 0,
    
    -- Additional Function Keys
    ['F13'] = 58,
    ['F14'] = 59,
    ['F15'] = 60,
    ['F16'] = 61,
    ['F17'] = 62,
    ['F18'] = 63,
    ['F19'] = 64,
    ['F20'] = 65,
    ['F21'] = 66,
    ['F22'] = 67,
    ['F23'] = 68,
    ['F24'] = 69,
    
    -- International Keys
    ['WORLD_0'] = 70,
    ['WORLD_1'] = 71,
    ['WORLD_2'] = 72,
    
    -- Additional Modifier Keys
    ['LSHIFT'] = 21,
    ['RSHIFT'] = 21,
    ['LCTRL'] = 36,
    ['RCTRL'] = 36,
    ['LALT'] = 19,
    ['RALT'] = 19,
    ['LWIN'] = 0,
    ['RWIN'] = 0,
    ['MENU'] = 0,
    
    -- Additional Numpad Keys
    ['KP_0'] = 96,
    ['KP_1'] = 97,
    ['KP_2'] = 98,
    ['KP_3'] = 99,
    ['KP_4'] = 100,
    ['KP_5'] = 101,
    ['KP_6'] = 102,
    ['KP_7'] = 103,
    ['KP_8'] = 104,
    ['KP_9'] = 105,
    ['KP_PERIOD'] = 107,
    ['KP_DIVIDE'] = 99,
    ['KP_MULTIPLY'] = 100,
    ['KP_MINUS'] = 97,
    ['KP_PLUS'] = 96,
    ['KP_ENTER'] = 201,
    ['KP_EQUALS'] = 83,
}
