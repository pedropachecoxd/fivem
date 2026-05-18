fx_version 'cerulean'
game 'gta5'

author 'Pacheco'
description 'Telemóvel Pacheco_phone - Estilo PT com Item'
version '1.2.0'

ui_page 'html/index.html'

shared_scripts {
    '@es_extended/imports.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}