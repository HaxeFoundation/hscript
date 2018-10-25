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

typedef CNamedType = {
	var name : String;
	var params : Array<TType>;
}

typedef CClass = {> CNamedType,
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

typedef CEnum = {> CNamedType,
	var constructors : Map<String,TType>;
}

typedef CTypedef = {> CNamedType,
	var t : TType;
}

typedef CAbstract = {> CNamedType,
}

@:allow(hscript.Checker)
class CheckerTypes {

	var types : Map<String,CTypedecl> = new Map();
	var t_string : TType;
	var localParams : Map<String,TType>;

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
				localParams = [for( t in cl.params ) c.path+"."+Checker.typeStr(t) => t];
				if( c.superClass != null )
					cl.superClass = getType(c.superClass.path, [for( t in c.superClass.params ) makeXmlType(t)]);
				var pkeys = [];
				for( f in c.fields ) {
					if( f.isOverride || f.name.substr(0,4) == "get_" || f.name.substr(0,4) == "set_" ) continue;
					var skip = false;
					for( m in f.meta )
						if( m.name == ":noScript" ) {
							skip = true;
							break;
						}
					if( skip ) continue;
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
				localParams = [for( t in en.params ) e.path+"."+Checker.typeStr(t) => t];
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
			};
			for( p in a.params )
				ta.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in ta.params ) a.path+"."+Checker.typeStr(t) => t];
				localParams = null;
			});
			types.set(a.path, CTAbstract(ta));
		}
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
		if( t == null )
			return TUnresolved(name); // most likely private class
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
	public var allowAsync : Bool;
	public var allowReturn : Null<TType>;

	public function new( ?types ) {
		if( types == null ) types = new CheckerTypes();
		this.types = types;
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

	public function check( expr : Expr, ?withType : WithType ) {
		if( withType == null ) withType = NoValue;
		locals = new Map();
		return typeExpr(expr,withType);
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
			var ct = types.resolve(path.join("."),params == null ? [] : [for( p in params ) makeType(t,e)]);
			if( ct == null ) error("Unknown type "+path, e);
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
		}
	}

	public static function typeStr( t : TType ) {
		inline function makeArgs(args:Array<TType>) return args.length==0 ? "" : "<"+[for( t in args ) typeStr(t)].join(",")+">";
		return switch (t) {
		case TMono(r): r.r == null ? "Unknown" : typeStr(r.r);
		case TInst(c, args): c.name + makeArgs(args);
		case TEnum(e, args): e.name + makeArgs(args);
		case TType(t, args): t.name + makeArgs(args);
		case TAbstract(a, args): a.name + makeArgs(args);
		case TFun(args, ret): "(" + [for( a in args ) (a.opt?"?":"")+(a.name == "" ? "" : a.name+":")+typeStr(a.t)].join(", ")+") -> "+typeStr(ret);
		case TAnon(fields): "{" + [for( f in fields ) (f.opt?"?":"")+f.name+":"+typeStr(f.t)].join(", ")+"}";
		case TParam(name): name;
		case TNull(t): "Null<"+typeStr(t)+">";
		case TUnresolved(name): "?"+name;
		default: t.getName().substr(1);
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

	function tryUnify( t1 : TType, t2 : TType ) {
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
			return tryUnify(r1,r2);
		case [_, TDynamic]:
			return true;
		case [TDynamic, _]:
			return true;
		case [TAnon(a1),TAnon(a2)]:
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
		case [TInt, TFloat]:
			return true;
		case [TFun(_), TAbstract({ name : "haxe.Function" },_)]:
			return true;
		default:
		}
		return typeEq(t1,t2);
	}

	function unify( t1 : TType, t2 : TType, e : Expr ) {
		if( !tryUnify(t1,t2) )
			error(typeStr(t1)+" should be "+typeStr(t2),e);
	}

	function apply( t : TType, params : Array<TType>, args : Array<TType> ) {
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
		}
	}

	public function follow( t : TType ) {
		return switch( t ) {
		case TMono(r): if( r.r != null ) follow(r.r) else t;
		case TType(t,args): apply(t.t, t.params, args);
		case TNull(t): follow(t);
		default: t;
		}
	}

	public function getFields( t : TType ) {
		var fields = [];
		while( t != null ) {
			t = follow(t);
			switch( t ) {
			case TInst(c, args):
				for( fname in c.fields.keys() ) {
					var f = c.fields.get(fname);
					fields.push({ name : f.name, t : f.t });
				}
				t = c.superClass;
			case TAnon(fl):
				for( f in fl )
					fields.push({ name : f.name, t : f.t });
				break;
			default:
			}
		}
		return fields;
	}

	function getField( t : TType, f : String, e : Expr ) {
		switch( follow(t) ) {
		case TInst(c, args):
			var cf = c.fields.get(f);
			if( cf == null && allowAsync ) {
				cf = c.fields.get("a_"+f);
				if( cf != null ) {
					var isPublic = true; // consider a_ prefixed as script specific
					cf = { isPublic : isPublic, params : cf.params, name : cf.name, t : unasync(cf.t) };
					if( cf.t == null ) cf = null;
				}
			}
			if( cf == null ) {
				if( c.superClass == null ) return null;
				var ft = getField(c.superClass, f, e);
				if( ft != null ) ft = apply(ft, c.params, args);
				return ft;
			}
			if( !cf.isPublic )
				error("Can't access private field "+f+" on "+c.name, e);
			return apply(cf.t, c.params, args);
		case TDynamic:
			return makeMono();
		case TAnon(fields):
			for( af in fields )
				if( af.name == f )
					return af.t;
			return null;
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

	function typeExpr( expr : Expr, withType : WithType ) : TType {
		switch( edef(expr) ) {
		case EConst(c):
			return switch (c) {
			case CInt(_): TInt;
			case CFloat(_): TFloat;
			case CString(_): types.t_string;
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
			switch( v ) {
			case "null":
				return makeMono();
			case "true", "false":
				return TBool;
			case "trace":
				return TDynamic;
			default:
				error("Unknown identifier "+v, expr);
			}
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
			var ft = typeExpr(e, Value);
			switch( follow(ft) ) {
			case TFun(args, ret):
				for( i in 0...params.length ) {
					var a = args[i];
					if( a == null ) error("Too many arguments", params[i]);
					var t = typeExpr(params[i], WithType(a.t));
					unify(t, a.t, params[i]);
				}
				for( i in params.length...args.length )
					if( !args[i].opt )
						error("Missing argument '"+args[i].name+"'", expr);
				return ret;
			case TDynamic:
				for( p in params ) typeExpr(p,Value);
				return makeMono();
			default:
				error(typeStr(ft)+" cannot be called", e);
			}
		case EField(o, f):
			var ot = typeExpr(o, Value);
			var ft = getField(ot, f, expr);
			if( ft == null )
				error(typeStr(ot)+" has no field "+f, expr);
			return ft;
		case ECheckType(v, t):
			var ct = makeType(t, expr);
			var vt = typeExpr(v, WithType(ct));
			unify(vt, ct, v);
			return ct;
		case EMeta(_, _, e):
			return typeExpr(e, withType);
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
			case WithType(follow(_) => TAnon(tfields)):
				var map = [for( f in tfields ) f.name => f];
				return TAnon([for( f in fl ) {
					var ft = map.get(f.name);
					if( ft == null ) error("Extra field "+f.name, f.e);
					{ t : typeExprWith(f.e, ft.t), opt : false, name : f.name }
				}]);
			default:
				return TAnon([for( f in fl ) { t : typeExpr(f.e, Value), opt : false, name : f.name }]);
			}
		case EBreak, EContinue:
			return TVoid;
		case EReturn(v):
			var et = v == null ? TVoid : typeExpr(v, allowReturn == null ? Value : WithType(allowReturn));
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
			if( et == null ) et = TDynamic;
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
			var tret = ret == null ? makeMono() : makeType(ret, expr);
			var locals = saveLocals();
			var oldRet = allowReturn;
			allowReturn = tret;
			var withArgs = null;
			if( name != null && !withType.match(WithType(follow(_) => TFun(_))) ) {
				var ev = events.get(name);
				if( ev != null ) withType = WithType(ev);
			}
			switch( withType ) {
			case WithType(follow(_) => TFun(args,ret)): withArgs = args; unify(tret,ret,expr);
			default:
			}
			var targs = [for( i in 0...args.length ) {
				var a = args[i];
				var at = a.t == null ? makeMono() : makeType(a.t, expr);
				if( withArgs != null && withArgs.length > i )
					unify(withArgs[i].t, at, expr);
				this.locals.set(a.name, at);
				{ name : a.name, opt : a.opt, t : at };
			}];

			typeExpr(body,NoValue);
			allowReturn = oldRet;
			this.locals = locals;
			var ft = TFun(targs,tret);
			if( name != null )
				locals.set(name, ft);
			return ft;
		case EUnop(op, _, e):
			var et = typeExpr(e, Value);
			switch( op ) {
			case "++", "--":
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
			var vt = switch( follow(itt) ) {
			case TInst({name:"Array"},[t]):
				t;
			default:
				var t = makeMono();
				var iter = makeIterator(t);
				unify(itt,iter,it);
				t;
			}
			this.locals.set(v, vt);
			typeExpr(e, Value);
			this.locals = locals;
			return TVoid;
		case EBinop(op, e1, e2):
			switch( op ) {
			case "&", "|", "^", ">>", ">>>", "<<":
				typeExprWith(e1,TInt);
				typeExprWith(e2,TInt);
				return TInt;
			case "=":
				var vt = typeExpr(e1, Value);
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
					unify(vt, ct, v);
				}
				var et = typeExpr(c.expr, withType);
				mergeType(et, c.expr);
			}
			if( defaultExpr != null )
				mergeType( typeExpr(defaultExpr, withType), defaultExpr);
			return withType == NoValue ? TVoid : tmin == null ? makeMono() : tmin;
		case ENew(cl, params):
		}
		error("Don't know how to type "+edef(expr).getName(), expr);
	}

}