@echo off
rm -rf release
mkdir release
cp haxelib.xml release
cd release
mkdir hscript
cd ..
cp hscript/*.hx release/hscript
haxe -xml release/haxedoc.xml hscript.Interp hscript.Parser hscript.Bytes hscript.Macro
7z a -tzip release.zip release
rm -rf release
haxelib submit release.zip
pause