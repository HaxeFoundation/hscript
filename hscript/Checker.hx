package hscript;
import hscript.Expr;

/**
	This is a special type that can be used in API.
	It will be type-checked as `Script` but will compile/execute as `Real`
**/
typedef TypeCheck<Real,Script> = Real;

enum TType {
	TMono( r : { r : TType } );
	TVoid;
	TInt;
	TFloat;
	TBool;
	TDynamic;
	TParam( name : String );
	TUnresolved( name : String );
	TNull( t : TType );
	TInst( c : CClass, args : Array<TType> );
	TEnum( e : CEnum, args : Array<TType> );
	TType( t : CTypedef, args : Array<TType> );
	TAbstract( a : CAbstract, args : Array<TType> );
	TFun( args : Array<{ name : String, opt : Bool, t : TType }>, ret : TType );
	TAnon( fields : Array<{ name : String, opt : Bool, t : TType }> );
	TLazy( f : Void -> TType );
}

private enum WithType {
	NoValue;
	Value;
	WithType( t : TType );
}

enum CTypedecl {
	CTClass( c : CClass );
	CTEnum( e : CEnum );
	CTTypedef( t : CTypedef );
	CTAlias( t : TType );
	CTAbstract( a : CAbstract );
}

typedef CMetadata = Array<{ name : String, params : Null<Array<Expr>> }>;

typedef CNamedType = {
	var name : String;
	var params : Array<TType>;
	var ?meta : CMetadata;
}

typedef CClass = {> CNamedType,
	var ?superClass : TType;
	var ?constructor : CField;
	var ?interfaces : Array<TType>;
	var ?isInterface : Bool;
	var fields : Map<String,CField>;
	var statics : Map<String,CField>;
	var ?staticClass : TType;
}

typedef CField = {
	var isPublic : Bool;
	var canWrite : Bool;
	var complete : Bool;
	var ?isMethod : Bool;
	var params : Array<TType>;
	var name : String;
	var t : TType;
	var ?meta : CMetadata;
}

typedef CEnum = {> CNamedType,
	var constructors : Array<{ name : String, ?args : Array<{ name : String, opt : Bool, t : TType }> }>;
	var ?enumClass : TType;
}

typedef CTypedef = {> CNamedType,
	var t : TType;
}

typedef CAbstract = {> CNamedType,
	var t : TType;
	var from : Array<TType>;
	var to : Array<TType>;
	var forwards : Map<String,Bool>;
	var impl : CClass;
}

class Completion {
	public var expr : Expr;
	public var t : TType;
	public function new(expr,t) {
		this.expr = expr;
		this.t = t;
	}
}

@:allow(hscript.Checker)
class CheckerTypes {

	var types : Map<String,CTypedecl> = new Map();
	var t_string : TType;
	var localParams : Map<String,TType>;
	var parser : hscript.Parser;

	public function new() {
		types = new Map();
		types.set("Void",CTAlias(TVoid));
		types.set("Int",CTAlias(TInt));
		types.set("Float",CTAlias(TFloat));
		types.set("Bool",CTAlias(TBool));
		types.set("Dynamic",CTAlias(TDynamic));
		parser = new hscript.Parser();
	}

	public function addXmlApi( api : Xml ) {
		var types = new haxe.rtti.XmlParser();
		types.process(api, "");
		var todo = [];
		for( v in types.root )
			addXmlType(v,todo);
		for( f in todo )
			f();
		t_string = getType("String");
	}

	public function defineClass( name : String, ?ct : CClass ) {
		if( ct == null )
			ct = {
				name : name,
				fields : [],
				statics : [],
				params : [],
			};
		types.set(name, CTClass(ct));
		return ct;
	}

	function addField(f:haxe.rtti.CType.ClassField) {
		if( f.isOverride || f.name.substr(0,4) == "get_" || f.name.substr(0,4) == "set_" )
			return null;
		var complete = !StringTools.startsWith(f.name,"__"); // __uid, etc. (no metadata in such fields)
		for( m in f.meta ) {
			if( m.name == ":noScript"  )
				return null;
			if( m.name == ":noCompletion" )
				complete = false;
		}
		var pkeys = [];
		var fl : CField = {
			isPublic : f.isPublic,
			canWrite : f.set.match(RNormal | RCall(_) | RDynamic),
			isMethod : f.set == RMethod || f.set == RDynamic,
			complete : complete,
			params : [],
			name : f.name,
			t : null
		};
		for( p in f.params ) {
			var pt = TParam(p);
			var key = f.name+"."+p;
			pkeys.push(key);
			fl.params.push(pt);
			localParams.set(key, pt);
		}
		fl.t = makeXmlType(f.type);
		if( f.meta != null && f.meta.length > 0 ) {
			fl.meta = [];
			for( m in f.meta )
				fl.meta.push({ name : m.name, params : [for( p in m.params ) try parser.parseString(p) catch( e : hscript.Expr.Error ) null] });
		}
		while( pkeys.length > 0 )
			localParams.remove(pkeys.pop());
		return fl;
	}

	function addXmlType(x:haxe.rtti.CType.TypeTree,todo:Array<Void->Void>) {
		switch (x) {
		case TPackage(name, full, subs):
			for( s in subs ) addXmlType(s,todo);
		case TClassdecl(c):
			if( types.exists(c.path) ) return;
			var cl : CClass = {
				name : c.path,
				params : [],
				fields : new Map(),
				statics : new Map(),
			};
			addMeta(c,cl);
			if( c.isInterface )
				cl.isInterface = true;
			for( p in c.params )
				cl.params.push(TParam(p));
			todo.push(function() {
				var params = cl.params;
				localParams = [for( t in cl.params ) c.path+"."+Checker.typeStr(t) => t];
				if( StringTools.endsWith(cl.name,"_Impl_") ) {
					for( a in types )
						switch( a ) {
						case CTAbstract(a) if( a.impl == cl ):
							for( t in a.params )
								localParams.set(a.name+"."+Checker.typeStr(t), t);
							break;
						default:
						}
				}
				if( c.superClass != null )
					cl.superClass = getType(c.superClass.path, [for( t in c.superClass.params ) makeXmlType(t)]);
				if( c.interfaces != null ) {
					cl.interfaces = [];
					for( i in c.interfaces )
						cl.interfaces.push(getType(i.path, [for( t in i.params ) makeXmlType(t)]));
				}
				for( f in c.fields ) {
					var f = addField(f);
					if( f != null ) {
						if( f.name == "new" )
							cl.constructor = f;
						else
							cl.fields.set(f.name, f);
					}
				}
				var stc : CClass = {
					name : "#"+cl.name,
					fields : [],
					statics: [],
					params: [],
				};
				cl.staticClass = TInst(stc,[]);
				for( f in c.statics ) {
					var f = addField(f);
					if( f != null ) {
						cl.statics.set(f.name, f);
						stc.fields.set(f.name, f);
					}
				}
				localParams = null;
			});
			types.set(cl.name, CTClass(cl));
		case TEnumdecl(e):
			if( types.exists(e.path) ) return;
			var en : CEnum = {
				name : e.path,
				params : [],
				constructors: [],
				enumClass: null,
			};
			addMeta(e,en);
			for( p in e.params )
				en.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in en.params ) e.path+"."+Checker.typeStr(t) => t];
				for( c in e.constructors )
					en.constructors.push({ name : c.name, args : c.args == null ? null : [for( a in c.args ) { name : a.name, opt : a.opt, t : makeXmlType(a.t) }] });
				localParams = null;
				var ent = TEnum(en,en.params);
				en.enumClass = TType({ name : "#"+en.name, params : [], t : TAnon([for( f in en.constructors ) { name : f.name, t : f.args == null ? ent : TFun(f.args,ent), opt : false }]) },[]);
			});
			types.set(en.name, CTEnum(en));
		case TTypedecl(t):
			if( types.exists(t.path) ) return;
			var td : CTypedef = {
				name : t.path,
				params : [],
				t : null,
			};
			for( p in t.params )
				td.params.push(TParam(p));
			if( t.path == "hscript.TypeCheck" )
				td.params.reverse();
			todo.push(function() {
				localParams = [for( pt in td.params ) t.path+"."+Checker.typeStr(pt) => pt];
				td.t = makeXmlType(t.type);
				localParams = null;
			});
			types.set(t.path, CTTypedef(td));
		case TAbstractdecl(a):
			if( types.exists(a.path) ) return;
			var ta : CAbstract = {
				name : a.path,
				params : [],
				t : null,
				from : [],
				to : [],
				forwards : new Map(),
				impl : null,
			};
			addMeta(a,ta);
			for( p in a.params )
				ta.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in ta.params ) a.path+"."+Checker.typeStr(t) => t];
				ta.t = makeXmlType(a.athis);
				for( f in a.from )
					if( f.field == null )
						ta.from.push(makeXmlType(f.t));
				for( t in a.to )
					if( t.field == null )
						ta.to.push(makeXmlType(t.t));
				for( m in a.meta )
					if( m.name == ":forward" && m.params != null ) {
						if( m.params.length == 0 )
							ta.forwards.set("*", true);
						for( i in m.params )
							ta.forwards.set(i, true);
					}
				localParams = null;
			});
			todo.unshift(function() {
				if( a.impl != null ) {
					var t = resolve(a.impl.path);
					if( t != null )
						switch( t ) {
						case TInst(c,_): ta.impl = c;
						default:
						}
				}
			});
			types.set(a.path, CTAbstract(ta));
		}
	}

	function addMeta( src : haxe.rtti.CType.TypeInfos, to : CNamedType ) {
		if( src.meta == null || src.meta.length == 0 )
			return;
		to.meta = [];
		for( m in src.meta )
			to.meta.push({ name : m.name, params : [for( p in m.params ) try parser.parseString(p) catch( e : hscript.Expr.Error ) null] });
	}

	function makeXmlType( t : haxe.rtti.CType.CType ) : TType {
		return switch (t) {
		case CUnknown: TUnresolved("Unknown");
		case CEnum(name, params): getType(name,[for( t in params ) makeXmlType(t)]);
		case CClass(name, params): getType(name,[for( t in params ) makeXmlType(t)]);
		case CTypedef(name, params): getType(name,[for( t in params ) makeXmlType(t)]);
		case CFunction(args, ret): TFun([for( a in args ) { name : a.name, opt : a.opt, t : makeXmlType(a.t) }], makeXmlType(ret));
		case CAnonymous(fields):
			inline function isOpt(m:haxe.rtti.CType.MetaData) {
				if( m == null ) return false;
				var b = false;
				for( m in m ) if( m.name == ":optional" ) { b = true; break; }
				return b;
			}
			TAnon([for( f in fields ) { name : f.name, t : makeXmlType(f.type), opt : isOpt(f.meta) }]);
		case CDynamic(t): TDynamic;
		case CAbstract(name, params):
			switch( name ) {
			default:
				getType(name,[for( t in params ) makeXmlType(t)]);
			}
		}
	}

	function getType( name : String, ?args : Array<TType> ) : TType {
		if( localParams != null ) {
			var t = localParams.get(name);
			if( t != null ) return t;
		}
		var t = resolve(name,args);
		if( t == null ) {
			var pack = name.split(".");
			if( pack.length > 1 ) {
				// bugfix for some args reported as pack._Name.Name while they are not private
				var priv = pack[pack.length-2];
				if( priv.charCodeAt(0) == "_".code ) {
					pack.remove(priv);
					return getType(pack.join("."), args);
				}
			}
			return TUnresolved(name); // most likely private class
		}
		return t;
	}

	public function resolve( name : String, ?args : Array<TType> ) : TType {
		if( name == "Null" ) {
			if( args == null || args.length != 1 ) throw "Missing Null<T> parameter";
			return TNull(args[0]);
		}
		var t = types.get(name);
		if( t == null ) return null;
		if( args == null ) args = [];
		return switch( t ) {
		case CTClass(c): TInst(c,args);
		case CTEnum(e): TEnum(e,args);
		case CTTypedef(t): TType(t,args);
		case CTAbstract(a): TAbstract(a, args);
		case CTAlias(t): t;
		}
	}

}

class Checker {

	public var types : CheckerTypes;
	var locals : Map<String,TType>;
	var globals : Map<String,TType> = new Map();
	var events : Map<String,TType> = new Map();
	var currentFunType : TType;
	var isCompletion : Bool;
	var allowDefine : Bool;
	var hasReturn : Bool;
	var callExpr : Expr;
	public var checkPrivate : Bool = true;
	public var allowAsync : Bool;
	public var allowReturn : Null<TType>;
	public var allowGlobalsDefine : Bool;
	public var allowUntypedMeta : Bool;
	public var allowPrivateAccess : Bool;
	public var allowNew : Bool;

	public function new( ?types ) {
		if( types == null ) types = new CheckerTypes();
		this.types = types;
	}

	public function setGlobals( cl : CClass, ?params : Array<TType>, allowPrivate = false ) {
		if( params == null )
			params = [for( p in cl.params ) makeMono()];
		while( true ) {
			for( f in cl.fields )
				if( f.isPublic || allowPrivate )
					setGlobal(f.name, f.params.length == 0 ? f.t : TLazy(function() {
						var t = apply(f.t,f.params,[for( i in 0...f.params.length) makeMono()]);
						return apply(t, cl.params, params);
					}));
			if( cl.superClass == null )
				break;
			cl = switch( cl.superClass ) {
			case TInst(csup,pl):
				params = [for( p in pl ) apply(p,cl.params,params)];
				csup;
			default: throw "assert";
			}
		}
	}

	public function removeGlobal( name : String ) {
		globals.remove(name);
	}

	public function setGlobal( name : String, type : TType ) {
		globals.set(name, type);
	}

	public function setEvent( name : String, type : TType ) {
		events.set(name, type);
	}

	public function getGlobals() {
		return globals;
	}

	function typeArgs( args : Array<Argument>, pos : Expr ) {
		return [for( i in 0...args.length ) {
			var a = args[i];
			var at = a.t == null ? makeMono() : makeType(a.t, pos);
			{ name : a.name, opt : a.opt, t : at };
		}];
	}

	public function check( expr : Expr, ?withType : WithType, ?isCompletion = false ) {
		if( withType == null ) withType = NoValue;
		locals = new Map();
		if( types.t_string == null )
			types.t_string = types.getType("String");
		allowDefine = allowGlobalsDefine;
		this.isCompletion = isCompletion;
		if( edef(expr).match(EFunction(_)) )
			expr = mk(EBlock([expr]), expr); // single function might be self recursive
		switch( edef(expr) ) {
		case EBlock(el):
			var delayed = [];
			var last = TVoid;
			for( e in el ) {
				while( true ) {
					switch( edef(e) ) {
					case EMeta(_,_,e2): e = e2;
					default: break;
					}
				}
				switch( edef(e) ) {
				case EFunction(args,_,name,ret) if( name != null ):
					var tret = ret == null ? makeMono() : makeType(ret, e);
					var ft = TFun(typeArgs(args,e),tret);
					locals.set(name, ft);
					delayed.push(function() {
						currentFunType = ft;
						typeExpr(e, NoValue);
						return ft;
					});
				default:
					for( f in delayed ) f();
					delayed = [];
					if( el[el.length-1] == e )
						last = typeExpr(e, withType);
					else
						typeExpr(e, NoValue);
				}
			}
			for( f in delayed )
				last = f();
			return last;
		default:
		}
		return typeExpr(expr,withType);
	}

	inline function edef( e : Expr ) {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	function punion( e1 : Expr, e2 : Expr ) : Expr {
		#if hscriptPos
		return {
			pmin : e1.pmin < e2.pmin ? e1.pmin : e2.pmin,
			pmax : e1.pmax > e2.pmax ? e1.pmax : e2.pmax,
			origin : e1.origin,
			line : e1.line < e2.line ? e1.line : e2.line,
			e : null,
		};
		#else
		return e1;
		#end
	}

	inline function error( msg : String, curExpr : Expr ) {
		var e = ECustom(msg);
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
		if( !isCompletion ) throw e;
	}

	function saveLocals() {
		return [for( k in locals.keys() ) k => locals.get(k)];
	}

	function makeType( t : CType, e : Expr ) : TType {
		return switch (t) {
		case CTPath(path, params):
			var params = params == null ? [] : [for( p in params ) makeType(p,e)];
			var ct = types.resolve(path.join("."),params);
			if( ct == null ) {
				// maybe a subtype that is public ?
				var pack = path.copy();
				var name = pack.pop();
				if( pack.length > 0 && pack[pack.length-1].charCodeAt(0) >= 'A'.code && pack[pack.length-1].charCodeAt(0) <= 'Z'.code ) {
					pack.pop();
					pack.push(name);
					ct = types.resolve(pack.join("."), params);
				}
			}
			if( ct == null ) {
				error("Unknown type "+path, e);
				ct = TDynamic;
			}
			return ct;
		case CTFun(args, ret):
			var i = 0;
			return TFun([for( a in args ) { name : "p"+(i++), opt : false, t : makeType(a,e) }], makeType(ret,e));
		case CTAnon(fields):
			return TAnon([for( f in fields ) { name : f.name, opt : false, t : makeType(f.t,e) }]);
		case CTParent(t):
			return makeType(t,e);
		case CTNamed(n, t):
			return makeType(t,e);
		case CTOpt(t):
			return makeType(t,e);
		case CTExpr(_):
			error("Unsupported expr type parameter", e);
			return null;
		}
	}

	public static function typeStr( t : TType ) {
		inline function makeArgs(args:Array<TType>) return args.length==0 ? "" : "<"+[for( t in args ) typeStr(t)].join(",")+">";
		return switch (t) {
		case TMono(r): r.r == null ? "Unknown" : typeStr(r.r);
		case TInst(c, args): c.name + makeArgs(args);
		case TEnum(e, args): e.name + makeArgs(args);
		case TType(t, args):
			if( t.name == "hscript.TypeCheck" )
				typeStr(args[1]);
			else
				t.name + makeArgs(args);
		case TAbstract(a, args): a.name + makeArgs(args);
		case TFun(args, ret): "(" + [for( a in args ) (a.opt?"?":"")+(a.name == "" ? "" : a.name+":")+typeStr(a.t)].join(", ")+") -> "+typeStr(ret);
		case TAnon(fields): "{" + [for( f in fields ) (f.opt?"?":"")+f.name+":"+typeStr(f.t)].join(", ")+"}";
		case TParam(name): name;
		case TNull(t): "Null<"+typeStr(t)+">";
		case TUnresolved(name): "?"+name;
		default: t.getName().substr(1);
		}
	}

	public static function typeIter( t : TType, callb : TType -> Void ) {
		switch( t ) {
		case TMono(r) if( r.r != null ): callb(r.r);
		case TNull(t): callb(t);
		case TInst(_,tl), TAbstract(_,tl), TEnum(_,tl), TType(_,tl):
			for( t in tl ) callb(t);
		case TFun(args,ret):
			for( t in args ) callb(t.t);
			callb(ret);
		case TAnon(fl):
			for( f in fl )
				callb(f.t);
		case TLazy(f):
			callb(f());
		default:
		}
	}

	function linkLoop( a : TType, t : TType ) {
		if( t == a ) return true;
		switch( t ) {
		case TMono(r):
			if( r.r == null ) return false;
			return linkLoop(a,r.r);
		case TEnum(_,tl), TInst(_,tl), TType(_,tl), TAbstract(_,tl):
			for( t in tl )
				if( linkLoop(a,t) )
					return true;
			return false;
		case TFun(args,ret):
			for( arg in args )
				if( linkLoop(a,arg.t) )
					return true;
			return linkLoop(a,ret);
		case TDynamic:
			if( t == TDynamic )
				return false;
			return linkLoop(a,TDynamic);
		case TAnon(fl):
			for( f in fl )
				if( linkLoop(a, f.t) )
					return true;
			return false;
		default:
			return false;
		}
	}

	function link( a : TType, b : TType, r : { r : TType } ) {
		if( linkLoop(a,b) )
			return follow(b) == a;
		if( b == TDynamic )
			return true;
		r.r = b;
		return true;
	}

	function typeEq( t1 : TType, t2 : TType ) {
		if( t1 == t2 )
			return true;
		switch( [t1,t2] ) {
		case [TMono(r), _]:
			if( r.r == null ) {
				if( !link(t1,t2,r) )
					return false;
				r.r = t2;
				return true;
			}
			return typeEq(r.r, t2);
		case [_, TMono(r)]:
			if( r.r == null ) {
				if( !link(t2,t1,r) )
					return false;
				r.r = t1;
				return true;
			}
			return typeEq(t1, r.r);
		case [TType(t1,pl1),TType(t2,pl2)] if( t1 == t2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TType(t1,pl1), _]:
			return typeEq(apply(t1.t, t1.params, pl1), t2);
		case [_,TType(t2,pl2)]:
			return typeEq(t1, apply(t2.t, t2.params, pl2));
		case [TInst(cl1,pl1), TInst(cl2,pl2)] if( cl1 == cl2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TEnum(e1,pl1), TEnum(e2,pl2)] if( e1 == e2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TAbstract(a1,pl1), TAbstract(a2,pl2)] if( a1 == a2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TNull(t1), TNull(t2)]:
			return typeEq(t1,t2);
		case [TNull(t1), _]:
			return typeEq(t1,t2);
		case [_, TNull(t2)]:
			return typeEq(t1,t2);
		case [TFun(args1,r1), TFun(args2,r2)] if( args1.length == args2.length ):
			for( i in 0...args1.length )
				if( !typeEq(args1[i].t, args2[i].t) )
					return false;
			return typeEq(r1, r2);
		case [TAnon(a1),TAnon(a2)] if( a1.length == a2.length ):
			var m = new Map();
			for( f in a2 )
				m.set(f.name, f);
			for( f1 in a1 ) {
				var f2 = m.get(f1.name);
				if( f2 == null ) return false;
				if( !typeEq(f1.t,f2.t) )
					return false;
			}
			return true;
		default:
		}
		return false;
	}

	public function tryUnify( t1 : TType, t2 : TType ) {
		if( t1 == t2 )
			return true;
		switch( [t1,t2] ) {
		case [TMono(r), _]:
			if( r.r == null ) {
				if( !link(t1,t2,r) )
					return false;
				r.r = t2;
				return true;
			}
			return tryUnify(r.r, t2);
		case [_, TMono(r)]:
			if( r.r == null ) {
				if( !link(t2,t1,r) )
					return false;
				r.r = t1;
				return true;
			}
			return tryUnify(t1, r.r);
		case [TType(t1,pl1), _]:
			return tryUnify(apply(t1.t, t1.params, pl1), t2);
		case [_,TType(t2,pl2)]:
			return tryUnify(t1, apply(t2.t, t2.params, pl2));
		case [TNull(t1), _]:
			return tryUnify(t1,t2);
		case [_, TNull(t2)]:
			return tryUnify(t1,t2);
		case [TFun(args1,r1),TFun(args2,r2)] if( args1.length == args2.length ):
			for( i in 0...args1.length ) {
				var a1 = args1[i];
				var a2 = args2[i];
				if( a2.opt && !a1.opt ) return false;
				if( !tryUnify(a2.t, a1.t) ) return false;
			}
			if( follow(r2) == TVoid )
				return true;
			return tryUnify(r1,r2);
		case [_, TDynamic]:
			return true;
		case [TDynamic, _]:
			return true;
		case [TAnon(a1),TAnon(a2)]:
			if( a2.length == 0 ) // always unify with {}
				return true;
			var m = new Map();
			for( f in a1 )
				m.set(f.name, f);
			for( f2 in a2 ) {
				var f1 = m.get(f2.name);
				if( f1 == null ) {
					if( f2.opt ) continue;
					return false;
				}
				if( !typeEq(f1.t,f2.t) )
					return false;
			}
			return true;
		case [TInst(cl1,pl1), TInst(cl2,pl2)]:
			while( cl1 != cl2 ) {
				if( cl1.interfaces != null ) {
					for( i in cl1.interfaces ) {
						switch( i ) {
						case TInst(cli, args):
							var i = TInst(cli, [for( a in args ) apply(a, cl1.params, pl1)]);
							if( tryUnify(i, t2) )
								return true;
						default:
							throw "assert";
						}
					}
				}
				switch( cl1.superClass ) {
				case null: return false;
				case TInst(c, args):
					pl1 = [for( a in args ) apply(a,cl1.params,pl1)];
					cl1 = c;
				default: throw "assert";
				}
			}
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TInst(cl1,pl1),TAnon(fl)]:
			for( i in 0...fl.length ) {
				var f2 = fl[i];
				var f1 = null;
				var cl = cl1;
				while( true ) {
				 	f1 = cl.fields.get(f2.name);
					if( f1 != null ) break;
					if( cl.superClass == null )
						return false;
					cl = switch( cl.superClass ) {
					case TInst(c,_): c;
					default: throw "assert";
					}
				}
				if( !typeEq(apply(f1.t,cl1.params,pl1),f2.t) )
					return false;
			}
			return true;
		case [TInt, TFloat]:
			return true;
		case [TFun(_), TAbstract({ name : "haxe.Function" },_)]:
			return true;
		case [_, TAbstract(a, args)]:
			for( ft in a.from ) {
				var t = apply(ft,a.params,args);
				if( tryUnify(t1,t) )
					return true;
			}
		case [TAbstract(a, args), _]:
			for( tt in a.to ) {
				var t = apply(tt,a.params,args);
				if( tryUnify(t,t2) )
					return true;
			}
		default:
		}
		return typeEq(t1,t2);
	}

	public function unify( t1 : TType, t2 : TType, e : Expr ) {
		if( !tryUnify(t1,t2) && !abstractCast(t1,t2,e) )
			error(typeStr(t1)+" should be "+typeStr(t2),e);
	}

	public function abstractCast( t1 : TType, t2 : TType, e : Expr ) {
		var tf1 = follow(t1);
		var tf2 = follow(t2);
		switch( [tf1,tf2] ) {
		case [TInst(c,[]),TAbstract(a,[ct])] if( a.name == "Class" && c.name.charCodeAt(0) == '#'.code ):
			return tryUnify(types.resolve(c.name.substr(1)), ct);
		default:
		}
		#if !hscriptPos
		return false;
		#else
		return getAbstractCast(tf1,tf2,e,false) || getAbstractCast(tf2,tf1,e,true);
		#end
	}

	#if hscriptPos
	function getAbstractCast( from : TType, to : TType, e : Expr, isFrom : Bool ) {
		switch( from ) {
		case TAbstract(a, args) if( a.impl != null ):
			for( s in a.impl.statics ) {
				if( s.meta == null ) continue;
				var found = false;
				for( m in s.meta )
					if( m.name == (isFrom?":from":":to") ) {
						found = true;
						break;
					}
				if( !found ) continue;
				switch( s.t ) {
				case TFun([arg], _):
					var at = apply(arg.t, s.params, [for( _ in s.params ) makeMono()]);
					at = apply(at,a.params,args);
					var acc = mk(null,e);
					if( tryUnify(to,at) && resolveGlobal(a.impl.name,acc,Value,false) != null ) {
						e.e = ECall(mk(EField(acc,s.name),e),[mk(e.e,e)]);
						return true;
					}
				default:
				}
			}
		default:
		}
		return false;
	}
	#end

	public function apply( t : TType, params : Array<TType>, args : Array<TType> ) {
		if( args.length != params.length ) throw "Invalid number of type parameters";
		if( args.length == 0 )
			return t;
		var subst = new Map();
		for( i in 0...params.length )
			subst.set(params[i], args[i]);
		function map(t:TType) {
			var st = subst.get(t);
			if( st != null ) return st;
			return mapType(t,map);
		}
		return map(t);
	}

	public function mapType( t : TType, f : TType -> TType ) {
		switch (t) {
		case TMono(r):
			if( r.r == null ) return t;
			return f(t);
		case TVoid, TInt, TFloat,TBool,TDynamic,TParam(_), TUnresolved(_):
			return t;
		case TEnum(_,[]), TInst(_,[]), TAbstract(_,[]), TType(_,[]):
			return t;
		case TNull(t):
			return TNull(f(t));
		case TInst(c, args):
			return TInst(c, [for( t in args ) f(t)]);
		case TEnum(e, args):
			return TEnum(e, [for( t in args ) f(t)]);
		case TType(t, args):
			return TType(t, [for( t in args ) f(t)]);
		case TAbstract(a, args):
			return TAbstract(a, [for( t in args ) f(t)]);
		case TFun(args, ret):
			return TFun([for( a in args ) { name : a.name, opt : a.opt, t : f(a.t) }], f(ret));
		case TAnon(fields):
			return TAnon([for( af in fields ) { name : af.name, opt : af.opt, t : f(af.t) }]);
		case TLazy(l):
			return f(l());
		}
	}

	public function follow( t : TType ) {
		return switch( t ) {
		case TMono(r): if( r.r != null ) follow(r.r) else t;
		case TType(t,args): follow(apply(t.t, t.params, args));
		case TNull(t): follow(t);
		case TLazy(f): follow(f());
		default: t;
		}
	}

	public function followOnce( t : TType, withAbstracts=false ) {
		return switch( t ) {
		case TMono(r): if( r.r != null ) r.r else t;
		case TType(t,args): apply(t.t, t.params, args);
		case TLazy(f): f();
		case TNull(t) if( withAbstracts ): t;
		case TAbstract(a, args) if( withAbstracts ): apply(a.t,a.params,args);
		default: t;
		}
	}

	public function getFields( t : TType ) : Array<{ name : String, t : TType }> {
		var fields = [];
		switch( follow(t) ) {
		case TInst(c, args):
			var map = (t) -> apply(t,c.params,args);
			while( c != null ) {
				for( fname in c.fields.keys() ) {
					var f = c.fields.get(fname);
					if( !f.isPublic || !f.complete ) continue;
					var name = f.name, t = map(f.t);
					if( allowAsync && StringTools.startsWith(name,"a_") ) {
						t = unasync(t);
						name = name.substr(2);
					}
					fields.push({ name : name, t : t });
				}
				if( c.isInterface && c.interfaces != null ) {
					for( i in c.interfaces ) {
						for( f in getFields(i) )
							fields.push({ name : f.name, t : map(f.t) });
					}
				}
				if( c.superClass == null ) break;
				switch( c.superClass ) {
				case TInst(csup,args):
					var curMap = map;
					map = (t) -> curMap(apply(t,csup.params,args));
					c = csup;
				default:
					break;
				}
			}
		case TAnon(fl):
			for( f in fl )
				fields.push({ name : f.name, t : f.t });
		case TFun(args, ret):
			if( isCompletion )
				fields.push({ name : "bind", t : TFun(args,TVoid) });
		case TAbstract(a,pl):
			for( v in a.forwards.keys() ) {
				var t = getField(apply(a.t, a.params, pl), v, null, false);
				fields.push({ name : v, t : t});
			}
		default:
		}
		return fields;
	}

	function checkField( cf : CField, ct : CNamedType, args, forWrite, e ) {
		if( !cf.isPublic && checkPrivate )
			error("Can't access private field "+cf.name+" on "+ct.name, e);
		if( forWrite && !cf.canWrite )
			error("Can't write readonly field "+cf.name+" on "+ct.name, e);
		var t = cf.t;
		if( cf.params != null ) t = apply(t, cf.params, [for( i in 0...cf.params.length ) makeMono()]);
		return apply(t, ct.params, args);
	}

	function getField( t : TType, f : String, e : Expr, forWrite = false ) {
		switch( follow(t) ) {
		case TInst(c, args):
			var cf = c.fields.get(f);
			if( cf == null && allowAsync ) {
				cf = c.fields.get("a_"+f);
				if( cf != null ) {
					var isPublic = true; // consider a_ prefixed as script specific
					cf = { isPublic : isPublic, canWrite : false, params : cf.params, name : cf.name, t : unasync(cf.t), complete : cf.complete };
					if( cf.t == null ) cf = null;
				}
			}
			if( cf == null && c.isInterface && c.interfaces != null ) {
				for( i in c.interfaces ) {
					var ft = getField(i, f, e, forWrite);
					if( ft != null )
						return apply(ft, c.params, args);
				}
			}
			if( cf == null ) {
				if( c.superClass == null ) return null;
				var ft = getField(c.superClass, f, e, forWrite);
				if( ft != null ) ft = apply(ft, c.params, args);
				return ft;
			}
			return checkField(cf,c,args,forWrite,e);
		case TDynamic:
			return makeMono();
		case TAnon(fields):
			for( af in fields )
				if( af.name == f )
					return af.t;
			return null;
		case TAbstract(a,pl) if( a.forwards.exists(f) ):
			return getField(apply(a.t, a.params, pl), f, e, forWrite);
		#if hscriptPos
		case TAbstract(a, pl) if( a.impl != null ):
			var cf = a.impl.statics.get(f);
			if( cf == null ) {
				if( a.forwards.exists("*") )
					return getField(apply(a.t, a.params, pl), f, e, forWrite);
				return null;
			}
			var acc = mk(null,e);
			var impl = resolveGlobal(a.impl.name,acc,Value,false);
			if( impl == null )
				return null;
			var t = checkField(cf,a,pl,forWrite,e);
			switch( e.e ) {
			case EField(obj, f):
				if( cf.isMethod ) {
					switch( callExpr?.e ) {
					case null:
					case ECall(ec,params) if( ec == e ):
						e.e = EField(acc,f);
						params.unshift(mk(ECast(obj),obj));
						return t;
					default:
					}
				} else {
					e.e = ECall(mk(EField(acc,"get_"+f),e),[obj]);
					return t;
				}
			default:
			}
			return null;
		#end
		default:
			return null;
		}
	}

	public function unasync( t : TType ) : TType {
		switch( follow(t) ) {
		case TFun(args, ret) if( args.length > 0 ):
			var rargs = args.copy();
			switch( follow(rargs.shift().t) ) {
			case TFun([r],_): return TFun(rargs,r.t);
			default:
			}
		default:
		}
		return null;
	}

	function typeExprWith( expr : Expr, t : TType ) {
		var et = typeExpr(expr, WithType(t));
		unify(et, t, expr);
		return t;
	}

	function makeMono() {
		return TMono({r:null});
	}

	function makeIterator(t) : TType {
		return TAnon([{ name : "next", opt : false, t : TFun([],t) }, { name : "hasNext", opt : false, t : TFun([],TBool) }]);
	}

	function mk(e,p) : Expr {
		#if hscriptPos
		return { e : e, pmin : p.pmin, pmax : p.pmax, origin : p.origin, line : p.line };
		#else
		return e;
		#end
	}

	function isString( t : TType ) {
		t = follow(t);
		return t.match(TInst({name:"String"},_));
	}

	function onCompletion( expr : Expr, t : TType ) {
		if( isCompletion ) throw new Completion(expr, t);
	}

	function typeField( o : Expr, f : String, expr : Expr, withType, forWrite : Bool ) {
		if( f == null && isCompletion ) {
			var ot = typeExpr(o, Value);
			onCompletion(expr,ot);
			return TDynamic;
		}
		var path = [{ f : f, e : expr }];
		while( true ) {
			switch( edef(o) ) {
			case EField(e,f) if( f != null ):
				path.unshift({ f : f, e : o });
				o = e;
			case EIdent(i):
				path.unshift({ f : i, e : o });
				return typePath(path, withType, forWrite);
			default:
				break;
			}
		}
		return readPath(typeExpr(o, Value), path, forWrite);
	}

	function patchStubAccess( ef : Expr ) {
		#if hscriptPos
		switch( ef.e ) {
		case EField(e, f):
			var g = types.resolve("hscript.Checker",[]);
			if( g == null ) return false;
			var acc = getTypeAccess(g, e);
			if( acc == null ) return false;
			e.e = acc;
			ef.e = EField(e,"stub_"+f);
			return true;
		default:
		}
		#end
		return false;
	}

	function readPath( ot : TType, path : Array<{ f : String, e : Expr }>, forWrite ) {
		for( p in path ) {
			var ft = getField(ot, p.f, p.e, p == path[path.length-1] ? forWrite : false);
			if( ft == null ) {
				switch( ot ) {
				case TInst(c, _) if( c.name == "#Std" ):
					// these two methods are extern in HL and we must provide
					// some stubs so they both type and execute
					switch( p.f ) {
					case "int":
						if( patchStubAccess(p.e) )
							return TFun([{ name : "value", opt : false, t : TFloat }],TInt);
					case "downcast":
						var ct = makeMono();
						var t = types.resolve("Class",[ct]);
						if( t != null && patchStubAccess(p.e) )
							return TFun([{ name : "value", opt : false, t : TDynamic }, { name : "cl", opt : false, t : t }],ct);
					default:
					}
				default:
				}
				error(typeStr(ot)+" has no field "+p.f, p.e);
				return TDynamic;
			}
			ot = ft;
		}
		return ot;
	}

	function typePath( path : Array<{ f : String, e : Expr }>, withType, forWrite : Bool ) {
		var root = path[0];
		var l = locals.get(root.f);
		if( l != null ) {
			path.shift();
			return readPath(l,path,forWrite);
		}
		var t = resolveGlobal(root.f,root.e,path.length == 1 ? withType : Value, forWrite && path.length == 1);
		if( t != null ) {
			path.shift();
			return readPath(t,path,forWrite);
		}
		var fields = [];
		while( path.length > 1 ) {
			var name = [for( p in path ) p.f].join(".");
			var union = punion(path[0].e,path[path.length-1].e);
			var t = resolveGlobal(name, union, Value, forWrite && fields.length == 0);
			if( t != null ) {
				#if hscriptPos
				if( union.e != null ) path[path.length-1].e.e = union.e;
				#end
				return readPath(t,fields,forWrite);
			}
			fields.unshift(path.pop());
		}
		if( !isCompletion )
			error("Unknown identifier "+root.f, root.e);
		return TDynamic;
	}

	function hasMeta( meta : Metadata, name : String ) {
		for( m in meta )
			if( m.name == name )
				return true;
		return false;
	}

	function resolveGlobal( name : String, expr : Expr, withType : WithType, forWrite : Bool ) : TType {
		var g = globals.get(name);
		if( g != null ) {
			return switch( g ) {
			case TLazy(f): f();
			default: g;
			}
		}
		if( allowAsync ) {
			g = globals.get("a_"+name);
			if( g != null ) g = unasync(g);
			if( g != null ) return g;
		}
		switch( name ) {
		case "null":
			return makeMono();
		case "true", "false":
			return TBool;
		case "trace":
			return TDynamic;
		default:
			#if hscriptPos
			var wt = switch( withType ) { case WithType(t): follow(t); default: null; };
			switch( wt ) {
			case null:
			// enum constructor resolution
			case TEnum(e, args):
				for( c in e.constructors )
					if( c.name == name ) {
						var acc = getTypeAccess(wt, expr, name);
						if( acc != null ) {
							expr.e = acc;
							var ct = c.args == null ? wt : TFun(c.args, wt);
							return apply(ct, e.params, args);
						}
						break;
					}
			// abstract enum resolution
			case TAbstract(a, args) if( hasMeta(a.meta,":enum") ):
				var f = a.impl.statics.get(name);
				if( f != null && hasMeta(f.meta,":enum") ) {
					var acc = getTypeAccess(TInst(a.impl,[]),expr,name);
					if( acc != null ) {
						expr.e = acc;
						return wt;
					}
				}
			default:
			}
			// this variable resolution
			var g = locals.get("this");
			if( g != null ) {
				// local this resolution
				var prev = checkPrivate;
				checkPrivate = false;
				var t = getField(g, name, expr);
				checkPrivate = prev;
				if( t != null ) {
					expr.e = EField(mk(EIdent("this"),expr),name);
					return t;
				}
				// static resolution
				switch( g ) {
				case TInst(c, _):
					var f = c.statics.get(name);
					if( f != null ) {
						var acc = getTypeAccess(g, expr, name);
						if( acc != null ) {
							expr.e = acc;
							return checkField(f,c,[for( a in f.params ) makeMono()], forWrite, expr);
						}
					}
				default:
				}
			}
			// type path resolution
			var t = types.getType(name);
			if( !t.match(TUnresolved(_)) ) {
				var acc = getTypeAccess(t, expr);
				if( acc != null ) {
					expr.e = acc;
					switch( t ) {
					case TInst(c,_) if( c.staticClass != null ):
						return c.staticClass;
					case TEnum(e,_):
						return e.enumClass;
					default:
						throw "assert";
					}
				}
			}
			#end
		}
		return null;
	}

	function getTypeAccess( t : TType, expr : Expr, ?field : String ) : ExprDef {
		return null;
	}

	function unifyCallParams( args : Array<{ name : String, opt : Bool, t : TType }>, params : Array<Expr>, pos : Expr ) {
		for( i in 0...params.length ) {
			var a = args[i];
			if( a == null ) {
				error("Too many arguments", params[i]);
				break;
			}
			var t = typeExpr(params[i], a == null ? Value : WithType(a.t));
			unify(t, a.t, params[i]);
		}
		for( i in params.length...args.length )
			if( !args[i].opt )
				error("Missing argument "+args[i].name+":"+typeStr(args[i].t), pos);
	}

	function typeExpr( expr : Expr, withType : WithType ) : TType {
		if( expr == null && isCompletion )
			return switch( withType ) {
			case WithType(t): t;
			default: TDynamic;
			}
		switch( edef(expr) ) {
		case EConst(c):
			return switch (c) {
			case CInt(_): TInt;
			case CFloat(_): TFloat;
			case CString(_): types.t_string;
			}
		case EIdent(v):
			return typePath([{ f : v, e : expr }],withType,false);
		case EBlock(el):
			var t = TVoid;
			var locals = saveLocals();
			for( e in el )
				t = typeExpr(e, e == el[el.length-1] ? withType : NoValue);
			this.locals = locals;
			return t;
		case EVar(n, t, init):
			var vt = t == null ? makeMono() : makeType(t, expr);
			if( init != null ) {
				var et = typeExpr(init, t == null ? Value : WithType(vt));
				if( t == null ) vt = et else unify(et,vt, init);
			}
			locals.set(n, vt);
			return TVoid;
		case EParent(e):
			return typeExpr(e,withType);
		case ECall(e, params):
			switch( edef(e) ) {
			case EField(val, "bind"):
				var ft = typeExpr(val, Value);
				switch( ft ) {
				case TFun(args,ret):
					var remainArgs = args.copy();
					for( p in params ) {
						var a = remainArgs.shift();
						if( a == null ) {
							error("Too many arguments", p);
							return TFun([], ret);
						}
						typeExprWith(p, a.t);
					}
					return TFun(remainArgs, ret);
				default:
				}
			default:
			}
			var prev = callExpr;
			callExpr = expr;
			var ft = typeExpr(e, switch( [edef(e),withType] ) {
				case [EIdent(_),WithType(TEnum(_))]: withType;
				default: Value;
			});
			callExpr = prev;
			switch( follow(ft) ) {
			case TFun(args, ret):
				unifyCallParams(args, params, expr);
				return ret;
			case TDynamic:
				for( p in params ) typeExpr(p,Value);
				return makeMono();
			default:
				error(typeStr(ft)+" cannot be called", e);
				return makeMono();
			}
		case EField(o, f):
			return typeField(o,f,expr,withType,false);
		case ECheckType(v, t):
			var ct = makeType(t, expr);
			var vt = typeExpr(v, WithType(ct));
			unify(vt, ct, v);
			return ct;
		case EMeta(m, args, e):
			return checkMeta(m,args,e,expr,withType);
		case EIf(cond, e1, e2), ETernary(cond, e1, e2):
			typeExprWith(cond, TBool);
			var t1 = typeExpr(e1, withType);
			if( e2 == null )
				return t1;
			var t2 = typeExpr(e2, withType);
			if( withType == NoValue )
				return TVoid;
			if( tryUnify(t2,t1) )
				return t1;
			if( tryUnify(t1,t2) )
				return t2;
			unify(t2,t1,e2); // error
		case EWhile(cond, e), EDoWhile(cond, e):
			typeExprWith(cond,TBool);
			typeExpr(e, NoValue);
			return TVoid;
		case EObject(fl):
			switch( withType ) {
			case WithType(follow(_) => TAnon(tfields)) if( tfields.length > 0 ):
				var map = [for( f in tfields ) f.name => f];
				return TAnon([for( f in fl ) {
					var ft = map.get(f.name);
					var ft = if( ft == null ) {
						error("Extra field "+f.name, f.e);
						TDynamic;
					} else ft.t;
					{ t : typeExprWith(f.e, ft), opt : false, name : f.name }
				}]);
			default:
				return TAnon([for( f in fl ) { t : typeExpr(f.e, Value), opt : false, name : f.name }]);
			}
		case EBreak, EContinue:
			return TVoid;
		case EReturn(v):
			var et = v == null ? TVoid : typeExpr(v, allowReturn == null ? Value : WithType(allowReturn));
			hasReturn = true;
			if( allowReturn == null )
				error("Return not allowed here", expr);
			else
				unify(et, allowReturn, v == null ? expr : v);
			return makeMono();
		case EArrayDecl(el):
			var et = null;
			for( v in el ) {
				var t = typeExpr(v, et == null ? Value : WithType(et));
				if( et == null ) et = t else if( !tryUnify(t,et) ) {
					if( tryUnify(et,t) ) et = t else unify(t,et,v);
				}
			}
			if( et == null ) et = makeMono();
			return types.getType("Array",[et]);
		case EArray(a, index):
			typeExprWith(index, TInt);
			var at = typeExpr(a, Value);
			switch( follow(at) ) {
			case TInst({ name : "Array"},[et]): return et;
			default: error(typeStr(at)+" is not an Array", a);
			}
		case EThrow(e):
			typeExpr(e, Value);
			return makeMono();
		case EFunction(args, body, name, ret):
			var ft = null, tret = null, targs = null;
			if( currentFunType != null ) {
				switch( currentFunType ) {
				case TFun(args,ret):
					ft = currentFunType;
					tret = ret; targs = args;
				default:
					throw "assert";
				}
				currentFunType = null;
			} else {
				tret = ret == null ? makeMono() : makeType(ret, expr);
			}
			var locals = saveLocals();
			var oldRet = allowReturn;
			var oldGDef = allowDefine;
			var oldHasRet = hasReturn;
			allowReturn = tret;
			allowDefine = false;
			hasReturn = false;
			var withArgs = null;
			if( name != null && !withType.match(WithType(follow(_) => TFun(_))) ) {
				var ev = events.get(name);
				if( ev != null ) withType = WithType(ev);
			}
			var isShortFun = switch( edef(body) ) {
			case EMeta(":lambda",_): true;
			default: false;
			}
			switch( withType ) {
			case WithType(follow(_) => TFun(args,ret)):
				withArgs = args;
				if( !isShortFun || follow(ret) != TVoid ) unify(tret,ret,expr);
			default:
			}
			if( targs == null )
				targs = typeArgs(args,expr);
			for( i in 0...targs.length ) {
				var a = targs[i];
				if( withArgs != null ) {
					if( i < withArgs.length )
						unify(withArgs[i].t, a.t, expr);
					else
						error("Extra argument "+a.name, expr);
				}
				this.locals.set(a.name, a.t);
			}
			if( withArgs != null && targs.length < withArgs.length )
				error("Missing "+(withArgs.length - targs.length)+" arguments ("+[for( i in targs.length...withArgs.length ) typeStr(withArgs[i].t)].join(",")+")", expr);
			typeExpr(body,NoValue);
			if( !hasReturn && !tryUnify(tret, TVoid) )
				error("Missing return "+typeStr(tret), expr);
			allowDefine = oldGDef;
			allowReturn = oldRet;
			hasReturn = oldHasRet;
			this.locals = locals;
			if( ft == null ) {
				ft = TFun(targs, tret);
				if( name != null ) locals.set(name, ft);
			}
			return ft;
		case EUnop(op, _, e):
			var et = typeExpr(e, Value);
			switch( op ) {
			case "++", "--", "-":
				unify(et,TInt,e);
				return et;
			case "!":
				unify(et,TBool,e);
				return et;
			default:
			}
		case EFor(v, it, e):
			var locals = saveLocals();
			var itt = typeExpr(it, Value);
			var vt = getIteratorType(itt, it);
			this.locals.set(v, vt);
			typeExpr(e, NoValue);
			this.locals = locals;
			return TVoid;
		case EForGen(it, e):
			Tools.getKeyIterator(it,function(vk,vv,it) {
				if( vk == null ) {
					error("Invalid for expression", it);
					return;
				}
				var locals = saveLocals();
				var itt = typeExpr(it, Value);
				var types = getKeyIteratorTypes(itt, it);
				this.locals.set(vk, types.key);
				this.locals.set(vv, types.value);
				typeExpr(e, NoValue);
				this.locals = locals;
			});
			return TVoid;
		case EBinop(op, e1, e2):
			switch( op ) {
			case "&", "|", "^", ">>", ">>>", "<<":
				typeExprWith(e1,TInt);
				typeExprWith(e2,TInt);
				return TInt;
			case "=":
				if( allowDefine ) {
					switch( edef(e1) ) {
					case EIdent(i) if( !locals.exists(i) && !globals.exists(i) ):
						var vt = typeExpr(e2,Value);
						locals.set(i, vt);
						return vt;
					default:
					}
				}
				var vt = switch( edef(e1) ) {
				case EIdent(v): typePath([{f:v,e:e1}],withType,true);
				case EField(o,f): typeField(o, f, e1, withType, true);
				default: typeExpr(e1,Value);
				}
				typeExprWith(e2,vt);
				return vt;
			case "+":
				var t1 = typeExpr(e1,WithType(TInt));
				var t2 = typeExpr(e2,WithType(t1));
				tryUnify(t1,t2);
				switch( [follow(t1), follow(t2)]) {
				case [TInt, TInt]:
					return TInt;
				case [TFloat, TInt], [TInt, TFloat], [TFloat, TFloat]:
					return TFloat;
				case [TDynamic, _], [_, TDynamic]:
					return TDynamic;
				case [t1,t2]:
					if( isString(t1) || isString(t2) )
						return types.t_string;
					unify(t1, TFloat, e1);
					unify(t2, TFloat, e2);
				}
			case "-", "*", "/", "%":
				var t1 = typeExpr(e1,WithType(TInt));
				var t2 = typeExpr(e2,WithType(t1));
				if( !tryUnify(t1,t2) )
					unify(t2,t1,e2);
				switch( [follow(t1), follow(t2)]) {
				case [TInt, TInt]:
					if( op == "/" ) return TFloat;
					return TInt;
				case [TFloat|TDynamic, TInt|TDynamic], [TInt|TDynamic, TFloat|TDynamic], [TFloat, TFloat]:
					return TFloat;
				default:
					unify(t1, TFloat, e1);
					unify(t2, TFloat, e2);
				}
			case "&&", "||":
				typeExprWith(e1,TBool);
				typeExprWith(e2,TBool);
				return TBool;
			case "...":
				typeExprWith(e1,TInt);
				typeExprWith(e2,TInt);
				return makeIterator(TInt);
			case "==", "!=":
				var t1 = typeExpr(e1,Value);
				var t2 = typeExpr(e2,WithType(t1));
				if( !tryUnify(t1,t2) )
					unify(t2,t1,e2);
				return TBool;
			case ">", "<", ">=", "<=":
				var t1 = typeExpr(e1,Value);
				var t2 = typeExpr(e2,WithType(t1));
				if( !tryUnify(t1,t2) )
					unify(t2,t1,e2);
				switch( follow(t1) ) {
				case TInt, TFloat, TBool, TInst({name:"String"},_):
				default:
					error("Cannot compare "+typeStr(t1), expr);
				}
				return TBool;
			case "??":
				var t1 = typeExpr(e1,withType);
				var t2 = typeExpr(e2,WithType(t1));
				if( tryUnify(t2,t1) )
					return t1;
				if( tryUnify(t1,t2) )
					return t2;
				unify(t2,t1,e2); // error
			case "is":
				typeExpr(e1,Value);
				var ct = typeExpr(e2,Value);
				switch( ct ) {
				case TType(t,_) if( t.name.charCodeAt(0) == "#".code ):
					// type check
				default:
					error("Should be a type",e2);
				}
				return TBool;
			default:
				if( op.charCodeAt(op.length-1) == "=".code ) {
					var t = typeExpr(mk(EBinop(op.substr(0,op.length-1),e1,e2),expr),withType);
					return typeExpr(mk(EBinop("=",e1,e2),expr), withType);
				}
				error("Unsupported operation "+op, expr);
			}
		case ETry(etry, v, et, ecatch):
			var vt = typeExpr(etry, withType);

			var old = locals.get(v);
			locals.set(v, makeType(et, ecatch));
			var ct = typeExpr(ecatch, withType);
			if( old != null ) locals.set(v,old) else locals.remove(v);

			if( withType == NoValue )
				return TVoid;
			if( tryUnify(vt,ct) )
				return ct;
			unify(ct,vt,ecatch);
			return vt;
		case ESwitch(value, cases, defaultExpr):
			var tmin = null;
			var vt = typeExpr(value, Value);
			inline function mergeType(t,p) {
				if( withType != NoValue ) {
					if( tmin == null )
						tmin = t;
					else if( !tryUnify(t,tmin) ) {
						unify(tmin,t, p);
						tmin = t;
					}
				}
			}
			for( c in cases ) {
				for( v in c.values ) {
					var ct = typeExpr(v, WithType(vt));
					unify(ct, vt, v);
				}
				var et = typeExpr(c.expr, withType);
				mergeType(et, c.expr);
			}
			if( defaultExpr != null )
				mergeType( typeExpr(defaultExpr, withType), defaultExpr);
			return withType == NoValue ? TVoid : tmin == null ? makeMono() : tmin;
		case ECast(e,t):
			var et = typeExpr(e, Value);
			return t == null ? makeMono() : makeType(t,expr);
		case ENew(cl, params):
			if( !allowNew ) error("'new' is not allowed", expr);
			var t = types.resolve(cl);
			if( t == null ) error("Unknown class "+cl, expr);
			switch( t ) {
			case TInst(c,_) if( c.constructor != null ):
				switch( c.constructor.t ) {
				case TFun(args, _):
					var ms = [for( c in c.params ) makeMono()];
					var mf = [for( c in c.constructor.params ) makeMono()];
					var args = [for( a in args ) { name : a.name, opt : a.opt, t : apply(apply(a.t,c.params,ms),c.constructor.params,mf) }];
					unifyCallParams(args, params, expr);
					return TInst(c, ms);
				default:
					throw "assert";
				}
			default:
				error(typeStr(t)+" cannot be constructed", expr);
			}
		}
		error("Don't know how to type "+edef(expr).getName(), expr);
		return TDynamic;
	}

	function checkMeta( m : String, args : Array<Expr>, next : Expr, expr : Expr, withType ) {
		if( m == ":untyped" && allowUntypedMeta )
			return makeMono();
		if( m == ":privateAccess" && allowPrivateAccess ) {
			var prev = checkPrivate;
			checkPrivate = false;
			var t = typeExpr(next, withType);
			checkPrivate = prev;
			return t;
		}
		return typeExpr(next, withType);
	}

	function getIteratorType( itt : TType, it : Expr ) {
		switch( follow(itt) ) {
		case TInst({name:"Array"},[t]):
			return t;
		default:
		}
		var ft = getField(itt,"iterator", it);
		if( ft == null )
			switch( itt ) {
			case TAbstract(a, args):
				// special case : we allow unconditional access
				// to an abstract iterator() underlying value (eg: ArrayProxy)
				var at = apply(a.t,a.params,args);
				return getIteratorType(at, it);
			default:
			}
		if( ft != null )
			switch( ft ) {
			case TFun([],ret): ft = ret;
			default: ft = null;
			}
		var t = makeMono();
		var iter = makeIterator(t);
		unify(ft != null ? ft : itt,iter,it);
		return t;
	}


	function getKeyIteratorTypes( itt : TType, it : Expr ) {
		switch( follow(itt) ) {
		case TInst({name:"Array"},[t]):
			return { key : TInt, value : t };
		default:
		}
		var ft = getField(itt,"keyValueIterator", it);
		if( ft == null )
			switch( itt ) {
			case TAbstract(a, args):
				// special case : we allow unconditional access
				// to an abstract keyValueIterator() underlying value (eg: ArrayProxy)
				var at = apply(a.t,a.params,args);
				return getKeyIteratorTypes(at, it);
			default:
			}
		if( ft != null )
			switch( ft ) {
			case TFun([],ret): ft = ret;
			default: ft = null;
			}
		var key = makeMono();
		var value = makeMono();
		var iter = makeIterator(TAnon([{name:"key",t:key,opt:false},{name:"value",t:value,opt:false}]));
		unify(ft != null ? ft : itt,iter,it);
		return { key : key, value : value };
	}

	static function stub_int( v : Float ) return Std.int(v);
	static function stub_downcast( v : Dynamic, cl : Dynamic ) return Std.downcast(v, cl);

}