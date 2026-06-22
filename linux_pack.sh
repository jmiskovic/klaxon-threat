zip -9q klaxon.lovr surface.jpg conf.lua boxxer.lua game.lua main.lua xplode.ogg levels.lua thump.ogg intro.ogg ambient.ogg jet.ogg klaxons.lua palettes.lua uber.frag dispensers.lua uber.vert fabrik.lua klaxon.ogg solids.lua point_light.lua dots.lua speck.lua PromptFont.otf serpent.lua

cat squashfs-root/lovr klaxon.lovr > squashfs-root/klaxon
chmod +x squashfs-root/klaxon
cd squashfs-root
~/Downloads/appimagetool-x86_64.AppImage .
mv LÖVR-x86_64.AppImage ../klaxon-x86_64.AppImage
cd ..
chmod +x klaxon-x86_64.AppImage
