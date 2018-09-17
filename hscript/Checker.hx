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
	public var allowReturn : Null<TType>;

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
		if( t == null )
			return TUnresolved(name); // most likely private class
		return t;
	}

	public function setGlobal( name : String, type : TType ) {
		globals.set(name, type);
	}

	public function getGlobals() {
		return globals;
	}

	public function check( expr : Expr, isValue = false ) {
		locals = new Map();
		return typeExpr(expr,isValue);
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

	function tryUnify( t1 : TType, t2 : TType ) {
		if( t1 == t2 )
			return true;
		return false;
	}

	function unify( t1 : TType, t2 : TType, e : Expr ) {
		if( !tryUnify(t1,t2) )
			error(typeStr(t1)+" should be "+typeStr(t2),e);
	}

	function apply( t : TType, params : Array<TType>, args : Array<TType> ) {
		if( args.length != params.length ) throw "Invalid number of type parameters";
		if( args.length != 0 ) throw "TODO";
		return t;
	}

	public function follow( t : TType ) {
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

	function typeExpr( expr : Expr, isValue : Bool = true ) : TType {
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
				t = typeExpr(e, isValue && e == el[el.length-1]);
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
			return typeExpr(e,isValue);
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
		case EMeta(_, _, e):
			return typeExpr(e, isValue);
		case EIf(cond, e1, e2), ETernary(cond, e1, e2):
			unify(typeExpr(cond), TBool, cond);
			var t1 = typeExpr(e1);
			if( e2 == null )
				return t1;
			var t2 = typeExpr(e2);
			if( !isValue )
				return TVoid;
			if( tryUnify(t2,t1) )
				return t1;
			if( tryUnify(t1,t2) )
				return t2;
			unify(t2,t1,e2); // error
		case EWhile(cond, e), EDoWhile(cond, e):
			unify(typeExpr(cond), TBool, cond);
			typeExpr(e);
			return TVoid;
		case EObject(fl):
			return TAnon([for( f in fl ) { t : typeExpr(f.e), opt : false, name : f.name }]);
		case EBreak, EContinue:
			return TVoid;
		case EReturn(v):
			var et = v == null ? TVoid : typeExpr(v);
			if( allowReturn == null )
				error("Return not allowed here", expr);
			else
				unify(et, allowReturn, v == null ? expr : v);
			return TDynamic;
		case EArrayDecl(el):
			var et = null;
			for( v in el ) {
				var t = typeExpr(v);
				if( et == null ) et = t else if( !tryUnify(t,et) ) {
					if( tryUnify(et,t) ) et = t else unify(t,et,v);
				}
			}
			if( et == null ) et = TDynamic;
			return getType("Array",[et]);
		case EArray(a, index):
			unify(typeExpr(index), TInt, index);
			var at = typeExpr(a);
			switch( follow(at) ) {
			case TInst({ name : "Array"},[et]): return et;
			default: error(typeStr(at)+" is not an Array", a);
			}
		case EThrow(e):
			typeExpr(e);
			return TDynamic;
		case EBinop(op, e1, e2):
		case EUnop(op, prefix, e):
		case EFor(v, it, e):
		case EFunction(args, e, name, ret):
		case ENew(cl, params):
		case ETry(e, v, t, ecatch):
		case ESwitch(e, cases, defaultExpr):
		}
		error("TODO "+edef(expr).getName(), expr);
	}

}