fx_version 'cerulean'
lua54 'on'
game 'gta5'

name 'ef_bridge'
description 'EmergencyForge bridge for FiveM: ignis tablets (eNOTF, FireTab), EMD sync, eNOTF billing and the Lex person sync'
author 'EmergencyForge.de'
-- Set from the release tag by the release build, a checkout of main stays 'dev'
version 'dev'

shared_scripts {
    'config.lua',
    'shared/url.lua',
    'shared/settings.lua'
}

client_scripts {
    'client/main.lua',
    'client/admin.lua'
}

-- core.lua first: every module builds on Bridge
server_scripts {
    'config_server.lua',
    'server/core.lua',
    'server/main.lua',
    'server/emd_sync.lua',
    'server/enotf_billing.lua',
    'server/billing-custom.lua',
    'server/lex_sync.lua',
    'server/admin.lua'
}

-- Master UI page hosts both tablets and the admin panel
ui_page 'html/master.html'

files {
    'html/master.html',
    'html/css/style.css',
    'html/css/firetab.css',
    'html/css/admin.css',
    'html/js/script.js',
    'html/js/firetab.js',
    'html/js/master.js',
    'html/js/admin.js'
}

data_file 'DLC_ITYP_REQUEST' 'stream/notfpad.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/firetab.ytyp'

escrow_ignore {
    'config.lua',
    'config_server.lua',
    'shared/*.lua',
    'client/*.lua',
    'server/core.lua',
    'server/main.lua',
    'server/enotf_billing.lua',
    'server/billing-custom.lua',
    'server/lex_sync.lua',
    'server/admin.lua',
    'html/**/*'
}
