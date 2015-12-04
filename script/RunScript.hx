package;

import haxe.*;
import hscript.*;
import sys.*;
import sys.io.*;
import sys.net.*;

#if neko
import neko.Lib;
#end
#if cpp
import cpp.Lib;
#end

class RunScript {
	
	public static function main () {
		
		var args = Sys.args ();
		var workingDirectory = args.pop();
			
		try {
			Sys.setCwd(workingDirectory);
		} catch (e:Dynamic) {
			error("Failed to set current working directory to [" + workingDirectory + "]");
		}

		if (args.length == 0) {
			error("Argument missing. Expected 1 got 0");
		}

		if (args[0] == "-f" || args[0] == "--file") {
			if (args.length == 1) {
				error("Argument missing. Expected 2 got 1");
			}
			if (args.length > 2) {
				error("Too many arguments. Expected 2 got " + args.length);
			}
			executeScriptFile(args[1]);
		}

		if (args[0] == "--help") {
			printHelp();
		}
		
		executeScript(args.join(" "));
	}
	
	static function executeScriptFile(scriptPath:String) {
		if (!FileSystem.exists(scriptPath)) {
			error("Specified file [" + scriptPath + "] not found");
		}
		if (FileSystem.isDirectory(scriptPath)) {
			error("Specified file [" + scriptPath + "] is a directory");
		}
		var script = File.getContent(scriptPath);
		executeScript(script);
	}
	
	static function executeScript(script:String) {
		var parser = new hscript.Parser();
		var program = parser.parseString(script);
		var interp = new hscript.Interp();
		
		// export some useful classes
		interp.variables.set("Array", Array);
		interp.variables.set("DateTools", DateTools);
		interp.variables.set("Math", Math);
		interp.variables.set("StringTools", StringTools);
		interp.variables.set("Sys", Sys);
		interp.variables.set("Xml", Xml);
		interp.variables.set("sys", {
			"FileSystem": sys.FileSystem,
			"io": {
				"File": sys.io.File
			},
			"net": {
				"Host": sys.net.Host
			}
		});
		interp.variables.set("haxe", {
			"Json": haxe.Json,
			"Http": haxe.Http,
			"Serializer": haxe.Serializer,
			"Unserializer": haxe.Unserializer
		});
		
		info(interp.execute(program));		
	}
	
	static function printHelp(exit:Bool = true) {
		var hscriptPath = getHaxelibPath("hscript");
		var meta:Dynamic = Json.parse(File.getContent(hscriptPath + "haxelib.json"));
		info('${meta.name} v${meta.version}');
		info('${meta.description}');
		info("");
		info("usage: haxelib run hscript SCRIPT");
		info("   or: haxelib run hscript -f SCRIPTPATH");
		info("   or: haxelib run hscript --file SCRIPTPATH");
		info("");
		info("examples:");
		info("   haxelib run hscript var x = 4; 1 + 2 * x");
		info("   9");
		info("");
		info("   haxelib run hscript \"5 | 6\"");
		info("   7");
		info("");
		info("   haxelib run hscript for(i in 0...5) Sys.stdout().writeString(i + ', '); 'done'");
		info("   0, 1, 2, 3, 4, done");
		info("");
		info("   haxelib run hscript sys.net.Host.localhost()");
		info("   mycomputer");
		info("");
		if(Sys.systemName() == "Windows") {
			info("   for /f %i in ('haxelib run hscript \"new sys.net.Host('')\"') do @set MY_IP=%i");
			info("   echo %MY_IP%");
		} else {
			info("   MY_IP=$(haxelib run hscript \"new sys.net.Host('')\"')");
			info("   echo $MY_IP");
		}
		info("   192.168.248.1");
		if(exit)
			Sys.exit(0);
	}
	
	static function info(msg:Dynamic) {
		Sys.stdout().writeString("" + msg + "\n");
	}
	
	static function error(msg:Dynamic, exit:Bool = true) {
		Sys.stderr().writeString("Error: " + msg + "!\n");
		if(exit)
			Sys.exit(1);
	}
	
	static function getHaxelibPath(libraryName:String):String {
		var proc = new Process("haxelib", ["path", libraryName]);
		var result = "";
		var ex:Dynamic = null;
		try {
			while(true)	{
				var line = proc.stdout.readLine();
				if (line.substr(0, 1) != "-")
					result = line;
			}
		} catch (e:Dynamic) { 
			ex = e;
		};
		proc.close();
		if (ex) error(ex);
		return result;
	}
}
