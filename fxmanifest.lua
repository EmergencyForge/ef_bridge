fx_version 'cerulean'
lua54 'on'
game 'gta5'

name 'intraTab'
description 'intraTab + NOTFpad + FireTab'
author 'EmergencyForge.de'
version '2.3.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua',
    'server/emd_sync.lua',
    'server/enotf_billing.lua',
    'server/billing-custom.lua'
}

-- Master UI Page (contains eNOTF and FireTab)
ui_page 'html/master.html'

files {
    'html/master.html',
    'html/index.html',
    'html/css/style.css',
    'html/js/script.js',
    'html/css/firetab.css',
    'html/js/firetab.js',
    'html/js/master.js'
}

data_file 'DLC_ITYP_REQUEST' 'stream/notfpad.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/firetab.ytyp'

escrow_ignore {
    'config.lua',
    'client/*.lua',
    'server/billing-custom.lua',
    'server/enotf_billing.lua',
    'server/main.lua',
    'html/**/*'
}