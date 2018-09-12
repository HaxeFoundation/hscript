package hscript;
import hscript.Expr;

enum TType {
	TMono;
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
	TFun( args : Array<{ name : String, opt : Bool, t : TType }>, ret : TType );
	TAnon( fields : Array<{ name : String, opt : Bool, t : TType }> );
}

enum CTypedecl {
	CTClass( c : CClass );
	CTEnum( e : CEnum );
	CTTypedef( t : CTypedef );
	CTAlias( t : TType );
}

typedef CClass = {
	var name : String;
	var params : Array<TType>;
	@:optional var superClass : TType;
	@:optional var constructor : CField;
	var fields : Map<String,CField>;
	var statics : Map<String,CField>;
}

typedef CField = {
	var isPublic : Bool;
	var params : Array<TType>;
	var name : String;
	var t : TType;
}

typedef CEnum = {
	var name : String;
	var params : Array<TType>;
	var constructors : Map<String,TType>;
}

typedef CTypedef = {
	var name : String;
	var params : Array<TType>;
	var t : TType;
}

class Checker {

	var types : Map<String,CTypedecl> = new Map();
	var locals : Map<String,TType>;
	var globals : Map<String,TType> = new Map();
	var t_string : TType;
	var localParams : Map<String,TType>;
	public var allowAsync : Bool;

	public function new() {
		types = new Map();
		types.set("Void",CTAlias(TVoid));
		types.set("Int",CTAlias(TInt));
		types.set("Float",CTAlias(TFloat));
		types.set("Bool",CTAlias(TBool));
		types.set("Dynamic",CTAlias(TDynamic));
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
			for( p in c.params )
				cl.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in cl.params ) c.path+"."+typeStr(t) => t];
				if( c.superClass != null )
					cl.superClass = getType(c.superClass.path, [for( t in c.superClass.params ) makeXmlType(t)]);
				var pkeys = [];
				for( f in c.fields )
					if( !f.isOverride ) {
						var fl : CField = { isPublic : f.isPublic, params : [], name : f.name, t : null };
						for( p in f.params ) {
							var pt = TParam(p);
							var key = f.name+"."+p;
							pkeys.push(key);
							fl.params.push(pt);
							localParams.set(key, pt);
						}
						fl.t = makeXmlType(f.type);
						while( pkeys.length > 0 )
							localParams.remove(pkeys.pop());
						if( fl.name == "new" )
							cl.constructor = fl;
						else
							cl.fields.set(f.name, fl);
					}
				localParams = null;
			});
			types.set(cl.name, CTClass(cl));
		case TEnumdecl(e):
			if( types.exists(e.path) ) return;
			var en : CEnum = {
				name : e.path,
				params : [],
				constructors: new Map(),
			};
			for( p in e.params )
				en.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in en.params ) e.path+"."+typeStr(t) => t];
				localParams = null;
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
			todo.push(function() {
				localParams = [for( pt in td.params ) t.path+"."+typeStr(pt) => pt];
				td.t = makeXmlType(t.type);
				localParams = null;
			});
			types.set(t.path, CTTypedef(td));
		case TAbstractdecl(a):
			if( types.exists(a.path) ) return;
			var td : CTypedef = {
				name : a.path,
				params : [],
				t : null,
			};
			for( p in a.params )
				td.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in td.params ) a.path+"."+typeStr(t) => t];
				td.t = makeXmlType(a.athis);
				localParams = null;
			});
			types.set(a.path, CTTypedef(td));
		}
	}

	function makeXmlType( t : haxe.rtti.CType.CType ) : TType {
		return switch (t) {
		case CUnknown: TMono;
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

	public function resolveType( name : String, ?args : Array<TType> ) : TType {
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
		case CTAlias(t): t;
		}
	}

	function getType( name : String, ?args : Array<TType> ) : TType {
		if( localParams != null ) {
			var t = localParams.get(name);
			if( t != null ) return t;
		}
		var t = resolveType(name,args);
		if( t == null ) {
			trace(name);
			return TUnresolved(name);
		}
		return t;
	}

	public function setGlobal( name : String, type : TType ) {
		globals.set(name, type);
	}

	public function check( expr : Expr ) {
		locals = new Map();
		return typeExpr(expr);
	}

	inline function edef( e : Expr ) {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	inline function error( msg : String, curExpr : Expr ) {
		var e = ECustom(msg);
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
		throw e;
	}

	function saveLocals() {
		return [for( k in locals.keys() ) k => locals.get(k)];
	}

	function makeType( t : CType, e : Expr ) : TType {
		return switch (t) {
		case CTPath(path, params):
			var ct = resolveType(path.join("."),[for( p in params ) makeType(t,e)]);
			if( ct == null ) error("Unknown type "+path, e);
			return ct;
		case CTFun(args, ret):
			var i = 0;
			return TFun([for( a in args ) { name : "p"+(i++), opt : false, t : makeType(a,e) }], makeType(ret,e));
		case CTAnon(fields):
			return TAnon([for( f in fields ) { name : f.name, opt : false, t : makeType(f.t,e) }]);
		case CTParent(t):
			return makeType(t,e);
		}
	}

	public function typeStr( t : TType ) {
		inline function makeArgs(args:Array<TType>) return args.length==0 ? "" : "<"+[for( a in args ) typeStr(t)].join(",")+">";
		return switch (t) {
		case TInst(c, args): c.name + makeArgs(args);
		case TEnum(e, args): e.name + makeArgs(args);
		case TType(t, args): t.name + makeArgs(args);
		case TFun(args, ret): "(" + [for( a in args ) (a.opt?"?":"")+a.name+":"+typeStr(a.t)].join(", ")+") -> "+typeStr(ret);
		case TAnon(fields): "{" + [for( f in fields ) (f.opt?"?":"")+f.name+":"+typeStr(f.t)].join(", ")+"}";
		case TParam(name): name;
		case TNull(t): "Null<"+typeStr(t)+">";
		case TUnresolved(name): "?"+name;
		default: t.getName().substr(1);
		}
	}

	function unify( t1 : TType, t2 : TType, e : Expr ) {
		if( t1 == t2 )
			return;
		error(typeStr(t1)+" should be "+typeStr(t2),e);
	}

	function apply( t : TType, params : Array<TType>, args : Array<TType> ) {
		if( args.length != params.length ) throw "Invalid number of type parameters";
		if( args.length != 0 ) throw "TODO";
		return t;
	}

	function follow( t : TType ) {
		return switch( t ) {
		case TType(t,args): apply(t.t, t.params, args);
		case TNull(t): follow(t);
		default: t;
		}
	}

	function getField( t : TType, f : String, e : Expr ) {
		switch( follow(t) ) {
		case TInst(c, args):
			var cf = c.fields.get(f);
			if( cf == null && allowAsync ) {
				cf = c.fields.get("a_"+f);
				if( cf != null ) {
					cf = { isPublic : cf.isPublic, params : cf.params, name : cf.name, t : unasync(cf.t) };
					if( cf.t == null ) cf = null;
				}
			}
			if( cf == null ) {
				if( c.superClass == null ) return null;
				var ft = getField(c.superClass, f, e);
				if( ft != null ) ft = apply(ft, c.params, args);
				return ft;
			}
			return apply(cf.t, c.params, args);
		case TDynamic:
			return TDynamic;
		default:
			return null;
		}
	}

	function unasync( t : TType ) : TType {
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

	function typeExpr( expr : Expr ) : TType {
		switch( edef(expr) ) {
		case EConst(c):
			return switch (c) {
			case CInt(_): TInt;
			case CFloat(_): TFloat;
			case CString(_): t_string;
			}
		case EIdent(v):
			var l = locals.get(v);
			if( l != null ) return l;
			var g = globals.get(v);
			if( g != null ) return g;
			if( allowAsync ) {
				g = globals.get("a_"+v);
				if( g != null ) g = unasync(g);
				if( g != null ) return g;
			}
			error("Unknown identifier "+v, expr);
		case EBlock(el):
			var t = TVoid;
			var locals = saveLocals();
			for( e in el )
				t = typeExpr(e);
			this.locals = locals;
			return t;
		case EVar(n, t, init):
			var vt = t == null ? TMono : makeType(t, expr);
			if( init != null ) {
				var et = typeExpr(init);
				if( t == null ) vt = et else unify(et,vt, init);
			}
			locals.set(n, vt);
			return TVoid;
		case EParent(e):
			return typeExpr(e);
		case ECall(e, eparams):
			var ft = typeExpr(e);
			var params = [for( e in eparams ) typeExpr(e)];
			switch( follow(ft) ) {
			case TFun(args, ret):
				for( i in 0...params.length ) {
					var a = args[i];
					if( a == null ) error("Too many arguments", eparams[i]);
					unify(params[i], a.t, eparams[i]);
				}
				for( i in params.length...args.length )
					if( !args[i].opt )
						error("Missing argument '"+args[i].name+"'", expr);
				return ret;
			case TDynamic:
				return TDynamic;
			default:
				error(typeStr(ft)+" cannot be called", e);
			}
		case EField(o, f):
			var ot = typeExpr(o);
			var ft = getField(ot, f, expr);
			if( ft == null )
				error(typeStr(ot)+" has no field "+f, expr);
			return ft;
		case EBinop(op, e1, e2):
		case EUnop(op, prefix, e):
		case EIf(cond, e1, e2):
		case EWhile(cond, e):
		case EFor(v, it, e):
		case EBreak, EContinue:
			return TVoid;
		case EFunction(args, e, name, ret):
		case EReturn(e):
		case EArray(e, index):
		case EArrayDecl(e):
		case ENew(cl, params):
		case EThrow(e):
		case ETry(e, v, t, ecatch):
		case EObject(fl):
		case ETernary(cond, e1, e2):
		case ESwitch(e, cases, defaultExpr):
		case EDoWhile(cond, e):
		case EMeta(name, args, e):
		}
		error("TODO "+edef(expr).getName(), expr);
	}

}