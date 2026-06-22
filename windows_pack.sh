zip -9q klaxon.lovr surface.jpg conf.lua boxxer.lua game.lua main.lua xplode.ogg levels.lua thump.ogg intro.ogg ambient.ogg jet.ogg klaxons.lua palettes.lua uber.frag dispensers.lua uber.vert fabrik.lua klaxon.ogg solids.lua point_light.lua dots.lua speck.lua PromptFont.otf serpent.lua

unzip -o ./lovr-x86_64.zip lovr.exe

cat lovr.exe klaxon.lovr > klaxon.exe
rm lovr.exe

unzip -o ./lovr-x86_64.zip '*.dll'
zip -9q klaxon-win64.zip klaxon.exe *.dll
rm *.dll
