fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

name 'pk_furtobestiame'
author 'camagoshi92'
description 'Furto bestiame: pecore con spinta realistica e allarmi ranch'
version '1.1.0'

shared_scripts {
  'config.lua'
}

client_scripts {
  'client.lua'
}

server_scripts {
  'server.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js',
  'html/background_item.png'
}

dependencies {
  'vorp_core'
}
