@echo off
set PATH="C:\Program Files\7-Zip";%PATH%
rm -rf release
mkdir release
cp haxelib.json README.md extraParams.hxml release
cd release
mkdir hscript
mkdir script
cd ..
cp hscript/*.hx release/hscript
cp script/*.hx* release/script
cd release/script
haxe build.hxml
cd ../..
haxe -xml release/haxedoc.xml hscript.Interp hscript.Parser hscript.Bytes hscript.Macro
7z a -tzip release.zip release
rm -rf release
haxelib submit release.zip
echo Remember to "git tag vX.Y.Z && git push --tags"
pause