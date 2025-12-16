package hscript;

import haxe.macro.Context;
import haxe.macro.Expr;

#if !hscriptPos
#error "LiveClass requires -D hscriptPos";
#end

class LiveClass {

	@:persistent static var CONFIG : { api : String, srcPath : Array<String> } #if !macro = getMacroConfig() #end;
	
	public static function isEnable() {
	   return CONFIG != null;
	}

	static macro function getMacroConfig() {
		return macro $v{CONFIG};
	}

	#if macro

	public static function enable( api : String, ?srcPath : Array<String> ) {
		if( api == null )
			CONFIG = null;
		else
			CONFIG = { api : api, srcPath : srcPath ?? [".","src"] }
	}

	static function hasRet( e : Expr ) : Bool {
		var ret : Null<Bool> = null;
		function loopRec( e : Expr ) {
			switch( e.expr ) {
			case EReturn(e):
				ret = (e != null);
			case EFunction(_):
			default:
				if( ret != null ) return;
				haxe.macro.ExprTools.iter(e, loopRec);
			}
		}
		loopRec(e);
		return ret;
	}

	public static function build() {
		if( CONFIG == null )
			return null;
		var fields = Context.getBuildFields();
		var bit = 0;
		var idents = [];
		for( f in fields ) {
			switch( f.kind ) {
			case FFun(m) if( f.access.indexOf(AStatic) < 0 ):
				var hasRet = m.ret == null ? hasRet(m.expr) : !m.ret.match(TPath({ name : "Void "}));
				var eargs = { expr : EArrayDecl([for( a in m.args ) macro $i{a.name}]), pos : f.pos };
				var interp = macro __INTERP.call(this, $v{bit},$eargs);
				var call = macro if( __INTERP_BITS & (1 << $v{bit}) != 0 ) ${hasRet ? macro return $interp : macro { $interp; return; }};
				idents.push(f.name);
				switch( m.expr.expr ) {
				case EBlock(b): b.unshift(call);
				default: m.expr = macro { $call; ${m.expr}; };
				}
				bit++;
			default:
			}
		}
		var pos = Context.currentPos();
		var noCompletion : Metadata = [{ name : ":noCompletion", pos : pos }];
		var cl = Context.getLocalClass().get();
		var className = cl.name;
		var classFile = getFilePath(pos);
		fields.push({
			name : "__interp_inst",
			pos : pos,
			access : [APrivate],
			meta : noCompletion,
			kind : FVar(macro : Dynamic),
		});
		fields.push({
			name : "__INTERP",
			pos : pos,
			access : [APrivate,AStatic],
			meta : noCompletion,
			kind : FVar(null,macro @:privateAccess new hscript.LiveClass.LiveClassRuntime($i{className}, $v{classFile}, $v{idents})),
		});
		fields.push({
			name : "__INTERP_BITS",
			pos : pos,
			access : [APrivate,AStatic],
			meta : noCompletion,
			kind : FVar(null, macro 0),
		});
		return fields;
	}

	public static function getFilePath( pos : Position ) {
		var filePath = Context.getPosInfos(pos).file.split("\\").join("/");
		var classPath = Context.getClassPath();
		classPath.push(Sys.getCwd());
		classPath.sort((c1,c2) -> c2.length - c1.length);
		for( path in classPath ) {
			path = path.split("\\").join("/");
			if( StringTools.startsWith(filePath,path) ) {
				filePath = filePath.substr(path.length);
				break;
			}
		}
		return filePath;
	}

	#elseif (sys || hxnodejs)

	// runtime

	public static function registerFile( file : String, onChange : Void -> Void ) {
		for( dir in CONFIG.srcPath ) {
			var path = dir+"/"+file;
			if( !sys.FileSystem.exists(path) ) continue;
			#if hl
			new hl.uv.Fs(null, path, function(ev) onChange());
			#else
			throw "Not implemented for this platform";
			#end
			return path;
		}
		return null;
	}

	static var types : hscript.Checker.CheckerTypes = null;
	public static function getTypes() {
		if( types != null )
			return types;
		if( CONFIG == null ) throw "Checker types were not configured";
		var xml = Xml.parse(sys.io.File.getContent(CONFIG.api));
		types = new Checker.CheckerTypes();
		types.addXmlApi(xml.firstElement());
		return types;
	}

	#end

}

#if !macro
class LiveClassRuntime {
	var cl : Class<Dynamic>;
	var type : hscript.Checker.TType;
	var className : String;
	var idents : Array<String>;
	var functions : Map<String,{ prev : String, value : hscript.Expr, index : Int }> = [];
	var newVars : Array<{ name : String, expr : hscript.Expr, type : Checker.TType }> = [];
	var compiledFields : Map<String,Bool>;
	var chk : Checker;
	var version = 0;
	public var path : String;
	public function new(cl, file, idents) {
		this.cl = cl;
		className = Type.getClassName(cl);
		this.idents = idents;
		this.path = LiveClass.registerFile(file, onChange);
		if( this.path != null ) haxe.Timer.delay(onChange,0);
	}

	function loadType() {
		type = LiveClass.getTypes().resolve(className);
		compiledFields = new Map();
		switch( type ) {
		case TInst(c,_):
			for( f in c.fields )
				compiledFields.set(f.name, true);
		default:
		}
	}

	function onChange() {
		if( type == null )
			loadType();
		try {
			var content = sys.io.File.getContent(path);
			var parser = new hscript.Parser();
			parser.allowTypes = true;
			parser.allowMetadata = true;
			parser.allowJSON = true;
			var defs = parser.parseModule(content,path);
			for( d in defs )
				switch( d ) {
				case DClass(c) if( c.name == className.split(".").pop() ):
					var todo : Array<hscript.Expr> = [];
					var done = [];
					for( cf in c.fields ) {
						if( cf.access.indexOf(AStatic) >= 0 )
							continue;
						switch( cf.kind ) {
						case KVar(v) if( !compiledFields.exists(cf.name) ):
							if( v.get != null || v.set != null )
								continue; // New properties not supported
							todo.push({ e : EVar(cf.name,v.type,v.expr), pmin : 0, pmax : 0, line : 0, origin : null });
							done.push(function(chk:Checker) {
								newVars.push({ name : cf.name, expr : v.expr, type : @:privateAccess chk.locals.get(cf.name) });
								compiledFields.set(cf.name, true);
							});
						case KFunction(f):
							var v = functions.get(cf.name);
							var code = hscript.Printer.toString(f.expr);
							if( v == null ) {
								v = { prev : code, value : null, index : idents.indexOf(cf.name) };
								functions.set(cf.name, v);
							} else if( v.prev != code ) {
								var e : hscript.Expr = { e : EFunction(f.args,f.expr,cf.name), line : f.expr.line, pmin : f.expr.pmin, pmax : f.expr.pmax, origin : f.expr.origin };
								todo.push(e);
								done.push(function(chk) {
									if( v.value == null && v.index >= 0 )
										(cl:Dynamic).__INTERP_BITS |= 1 << v.index;
									v.value = e;
									v.prev = code;
								});
							}
						default:
						}
					}
					if( todo.length > 0 ) {
						checkCode({ e : EBlock(todo), pmin : 0, pmax : 0, line : 0, origin : null }, done);
						version++;
					}
				default:
				}
		} catch( e : hscript.Expr.Error ) {
			log(Std.string(e));
		}
	}

	function checkCode( e : hscript.Expr, done : Array<Checker->Void> ) {
		var chk = new hscript.Checker(LiveClass.getTypes());
		chk.allowNew = true;
		chk.allowPrivateAccess = true;
		chk.setGlobal("this", type);
		for( v in newVars )
			chk.setGlobal(v.name, v.type);
		chk.check(e);
		for( f in done )
			f(chk);
		return e;
	}

	static function log( msg : String ) {
		#if sys
		Sys.println(msg);
		#else
		trace(msg);
		#end
	}

	public function call( obj : Dynamic, id : Int, args : Array<Dynamic> ) : Dynamic {
		var interp : LiveClassInterp = obj.__interp_inst;
		if( interp == null ) {
			interp = new LiveClassInterp();
			interp.variables.set("this", obj);
			obj.__interp_inst = interp;
		}
		if( interp.version != version ) {
			for( name => v in functions ) {
				if( v.value == null )
					continue;
				interp.execute(v.value);
				if( v.index >= 0 )
					interp.functions[v.index] = interp.variables.get(name);
			}
			interp.version = version;
			while( interp.newVarCount < newVars.length ) {
				var v = newVars[interp.newVarCount++];
				interp.variables.set(v.name, v.expr == null ? null : interp.execute(v.expr));
			}
		}
		return Reflect.callMethod(null,interp.functions[id],args);
	}
}

private class LiveClassInterp extends hscript.Interp {
	public var version = -1;
	public var newVarCount = 0;
	public var functions : Array<Dynamic> = [];
}
#end
