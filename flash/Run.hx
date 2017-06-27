import Sys.*;
import sys.FileSystem.*;
import sys.io.File.*;
import haxe.io.*;

class Run {
	// https://helpx.adobe.com/flash-player/kb/configure-debugger-version-flash-player.html
	static var flashlog(default, never) = switch (systemName()) {
		case "Linux":
			Path.join([getEnv("HOME"), ".macromedia/Flash_Player/Logs/flashlog.txt"]);
		case "Mac":
			Path.join([getEnv("HOME"), "Library/Preferences/Macromedia/Flash Player/Logs/flashlog.txt"]);
		case "Windows":
			Path.join([getEnv("APPDATA"), "Macromedia", "Flash Player", "Logs", "flashlog.txt"]);
		case _:
			throw "unsupported system";
	}
	static function main() {
		var args = args();
		var swf = args[0];
		var exitCode = switch (systemName()) {
			case "Linux":
				// The flash player has some issues with unexplained crashes,
				// but if it runs about 16 times, it should succeed one of those...
				var c = -1;
				for (i in 0...16) {
					if ((c = command("xvfb-run", ["-a", "flash/flashplayerdebugger", swf])) == 0)
						break;
					println('retry... (${i+1})');
					sleep(1.5);
				}
				c;
			case "Mac":
				command("/Applications/Flash Player Debugger.app/Contents/MacOS/Flash Player Debugger", [fullPath(swf)]);
			case "Windows":
				command("flash\\flashplayer.exe", [fullPath(swf)]);
			case _:
				throw "unsupported platform";
		}
		if (exists(flashlog))
			println(getContent(flashlog));
		else {
			println('does not exist: $flashlog');
			var parts = Path.normalize(flashlog).split("/");
			println(parts);
			for (i in 0...parts.length-1) {
				var path = parts.splice(0, i+1).join("/");
				println('ls $path');
				command("ls", [path]);
			}
		}
		exit(exitCode);
	}
}