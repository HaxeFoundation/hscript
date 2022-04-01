/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package hscript;
import hscript.Expr;


enum VarMode {
	Defined;
	ForceSync;
}

class Async {

	var definedVars : Array<{ n : String, prev : Null<VarMode> }>;
	var vars : Map<String,VarMode>;
	var currentFun : String;
	var currentLoop : Expr;
	var currentBreak : Expr -> Expr;
	var uid = 0;
	public var asyncIdents : Map<String,Bool>;

	static var nullExpr : Expr = #if hscriptPos { e : null, pmin : 0, pmax : 0, origin : "<null>", line : 0 } #else null #end;
	static var nullId = mk(EIdent("null"), nullExpr);

	inline static function expr( e : Expr ) {
		return #if hscriptPos e.e #else e #end;
	}

	inline static function mk( e, inf : Expr ) : Expr {
		return #if hscriptPos { e : e, pmin : inf.pmin, pmax : inf.pmax, origin : inf.origin, line : inf.line } #else e #end;
	}

	/**
		Convert a script into asynchronous one.
		- calls such as foo(a,b,c) are translated to a_foo(function(r) ...rest, a,b,c) where r is the result value
		- object access such obj.bar(a,b,c) are translated to obj.a_bar(function(r) ...rest, a, b, c)
		- @async expr will execute the expression but continue without waiting for it to finish
		- @split [ e1, e2, e3 ] is transformed to split(function(_) ...rest, [e1, e2, e3]) which
		  should execute asynchronously all expressions - until they return - before continuing the execution
		- for(i in v) block; loops are translated to the following:
			var _i = makeIterator(v);
			function _loop() {
				if( !_i.hasNext() ) return;
				var v = _i.next();
				block(function(_) _loop());
			}
			_loop()
		- while loops are translated similar to for loops
		- break and continue are correctly handled
		- you can use @sync <expr> to disable async transformation in some code parts (for performance reason)
		- a few expressions are still not supported (complex calls, try/catch, and a few others)

		In these examples ...rest represents the continuation of execution of the script after the expression
	**/
	public static function toAsync( e : Expr, topLevelSync = false ) {
		var a = new Async();
		return a.build(e, topLevelSync);
	}

	public dynamic function getTopLevelEnd() {
		return ignore();
	}

	public function build( e : Expr, topLevelSync = false ) {
		if( topLevelSync ) {
			return buildSync(e,null);
		} else {
			var end = getTopLevelEnd();
			return toCps(e, end, end);
		}
	}

	function defineVar( v : String, mode ) {
		definedVars.push({ n : v, prev : vars.get(v) });
		vars.set(v, mode);
	}

	function lookupFunctions( el : Array<Expr> ) {
		for( e in el )
			switch( expr(e) ) {
			case EFunction(_, _, name, _) if( name != null ): defineVar(name, Defined);
			case EMeta("sync",_,expr(_) => EFunction(_,_,name,_)) if( name != null ): defineVar(name, ForceSync);
			default:
			}
	}

	function buildSync( e : Expr, exit : Expr ) : Expr {
		switch( expr(e) ) {
		case EFunction(_,_,name,_):
			if( name != null )
				return toCps(e, null, null);
			return e;
		case EBlock(el):
			var v = saveVars();
			lookupFunctions(el);
			var e = block([for(e in el) buildSync(e,exit)], e);
			restoreVars(v);
			return e;
		case EMeta("async", _, e):
			return toCps(e, ignore(), ignore());
		case EMeta("sync", args, ef = expr(_) => EFunction(fargs, body, name, ret)):
			return mk(EMeta("sync",args,mk(EFunction(fargs, buildSync(body,null), name, ret),ef)),e);
		case EBreak if( currentBreak != null ):
			return currentBreak(e);
		case EContinue if( currentLoop != null ):
			return block([retNull(currentLoop, e), mk(EReturn(),e)],e);
		case EFor(_), EWhile(_):
			var oldLoop = currentLoop, oldBreak = currentBreak;
			currentLoop = null;
			currentBreak = null;
			e = Tools.map(e, buildSync.bind(_, exit));
			currentLoop = oldLoop;
			currentBreak = oldBreak;
			return e;
		case EReturn(eret) if( exit != null ):
			return block([eret == null ? retNull(exit, e) : call(exit,[eret], e), mk(EReturn(),e)], e);
		default:
			return Tools.map(e, buildSync.bind(_, exit));
		}
	}

	public function new() {
		vars = new Map();
		definedVars = [];
	}

	function ignore(?e) : Expr {
		var inf = e == null ? nullExpr : e;
		return fun("_", block(e == null ? [] : [e],inf));
	}

	inline function ident(str, e) {
		return mk(EIdent(str), e);
	}

	inline function fun(arg:String, e, ?name) {
		return mk(EFunction([{ name : arg, t : null }], e, name), e);
	}

	inline function funs(arg:Array<String>, e, ?name) {
		return mk(EFunction([for( a in arg ) { name : a, t : null }], e, name), e);
	}

	inline function block(arr:Array<Expr>, e) {
		if( arr.length == 1 && expr(arr[0]).match(EBlock(_)) )
			return arr[0];
		return mk(EBlock(arr), e);
	}

	inline function field(e, f, inf) {
		return mk(EField(e, f), inf);
	}

	inline function binop(op, e1, e2, inf) {
		return mk(EBinop(op, e1, e2), inf);
	}

	inline function call(e, args, inf) {
		return mk(ECall(e, args), inf);
	}

	function retNull(e:Expr,?pos) : Expr {
		switch( expr(e) ) {
		case EFunction([{name:"_"}], e, _, _): return e;
		default:
		}
		return call(e, [nullId], pos == null ? e : pos);
	}

	function makeCall( ecall, args : Array<Expr>, rest : Expr, exit, sync = false ) {
		var names = [for( i in 0...args.length ) "_a"+uid++];
		var rargs = [for( i in 0...args.length ) ident(names[i],ecall)];
		if( !sync )
			rargs.unshift(rest);
		var rest = mk(sync ? ECall(rest,[call(ecall, rargs,ecall)]) : ECall(ecall, rargs), ecall);
		var i = args.length - 1;
		while( i >= 0 ) {
			rest = toCps(args[i], fun(names[i], rest), exit);
			i--;
		}
		return rest;
	}

	var syncFlag : Bool;

	function isSync( e : Expr ) {
		syncFlag = true;
		checkSync(e);
		return syncFlag;
	}

	inline function isAsyncIdent( id : String ) {
		return asyncIdents == null || asyncIdents.exists(id);
	}

	function checkSync( e : Expr ) {
		if( !syncFlag )
			return;
		switch( expr(e) ) {
		case ECall(expr(_) => EIdent(i),_) if( isAsyncIdent(i) || vars.get(i) == Defined ):
			syncFlag = false;
		case ECall(expr(_) => EField(_,i),_) if( isAsyncIdent(i) ):
			syncFlag = false;
		case EFunction(_,_,name,_) if( name != null ):
			syncFlag = false;
		case EMeta("sync" | "async", _, _):
			// isolated from the sync part
		default:
			Tools.iter(e, checkSync);
		}
	}

	function saveVars() {
		return definedVars.length;
	}

	function restoreVars(k) {
		while( definedVars.length > k ) {
			var v = definedVars.pop();
			if( v.prev == null ) vars.remove(v.n) else vars.set(v.n, v.prev);
		}
	}

	public function toCps( e : Expr, rest : Expr, exit : Expr ) : Expr {
		if( isSync(e) )
			return call(rest, [buildSync(e, exit)],e);
		switch( expr(e) ) {
		case EBlock(el):
			var el = el.copy();
			var vold = saveVars();
			lookupFunctions(el);
			while( el.length > 0 ) {
				var e = toCps(el.pop(), rest, exit);
				rest = ignore(e);
			}
			restoreVars(vold);
			return retNull(rest);
		case EFunction(args, body, name, t):
			var vold = saveVars();
			if( name != null )
				defineVar(name, Defined);
			for( a in args )
				defineVar(a.name, Defined);
			args.unshift( { name : "_onEnd", t : null } );
			var frest = ident("_onEnd",e);
			var oldFun = currentFun;
			currentFun = name;
			var body = toCps(body, frest, frest);
			var f = mk(EFunction(args, body, name, t),e);
			restoreVars(vold);
			return rest == null ? f : call(rest, [f],e);
		case EParent(e):
			return mk(EParent(toCps(e, rest, exit)),e);
		case EMeta("sync", _, e):
			return call(rest,[buildSync(e,exit)],e);
		case EMeta("async", _, e):
			var nothing = ignore();
			return block([toCps(e,nothing,nothing),retNull(rest)],e);
		case EMeta("split", _, e):
			var args = switch( expr(e) ) { case EArrayDecl(el): el; default: throw "@split expression should be an array"; };
			var args = [for( a in args ) fun("_rest", toCps(block([a],a), ident("_rest",a), exit))];
			return call(ident("split",e), [rest, mk(EArrayDecl(args),e)],e);
		case ECall(expr(_) => EIdent(i), args):
			var mode = vars.get(i);
			return makeCall( ident( mode != null ? i : "a_" + i,e) , args, rest, exit, mode == ForceSync);
		case ECall(expr(_) => EField(e, f), args):
			return makeCall(field(e,"a_"+f,e), args, rest, exit);
		case EFor(v, eit, eloop):
			var id = ++uid;
			var it = ident("_i" + id,e);
			var oldLoop = currentLoop, oldBreak = currentBreak;
			var loop = ident("_loop" + id,e);
			currentLoop = loop;
			currentBreak = function(inf) return block([retNull(rest, inf), mk(EReturn(),inf)], inf);
			var efor = block([
				mk(EVar("_i" + id, call(ident("makeIterator",eit),[eit],eit)),eit),
				fun("_", block([
					mk(EIf(mk(EUnop("!", true, call( field(it, "hasNext", it), [], it)),it), currentBreak(it)),it),
					mk(EVar(v, call(field(it, "next",it), [], it)), it),
					toCps(eloop, loop, exit),
				], it),"_loop" + id),
				retNull(loop, e),
			], e);
			currentLoop = oldLoop;
			currentBreak = oldBreak;
			return efor;
		case EUnop(op = "!", prefix, eop):
			return toCps(eop, fun("_r",call(rest, [mk(EUnop(op, prefix, ident("_r",e)),e)], e)), exit);
		case EBinop(op, e1, e2):
			switch( op ) {
			case "=", "+=", "-=", "/=", "*=", "%=", "&=", "|=", "^=":
				switch( expr(e1) ) {
				case EIdent(_):
					var id = "_r" + uid++;
					return toCps(e2, fun(id, call(rest, [binop(op, e1, ident(id,e1),e1)], e1)), exit);
				case EField(ef1, f):
					var id1 = "_r" + uid++;
					var id2 = "_r" + uid++;
					return toCps(ef1, fun(id1, toCps(e2, fun(id2, call(rest, [binop(op, field(ident(id1, e1), f, ef1), ident(id2, e2), e)], e)), exit)), exit);
				case EArray(earr, eindex):
					var idArr = "_r" + uid++;
					var idIndex = "_r" + uid++;
					var idVal = "_r" + uid++;
					return toCps(earr,fun(idArr, toCps(eindex, fun(idIndex, toCps(e2,
						fun(idVal, call(rest, [binop(op, mk(EArray(ident(idArr,earr), ident(idIndex,eindex)),e1), ident(idVal,e1), e)], e))
					, exit)), exit)),exit);
				default:
					throw "assert " + e1;
				}
			case "||":
				var id1 = "_r" + uid++;
				var id2 = "_r" + uid++;
				return toCps(e1, fun(id1, mk(EIf(binop("==", ident(id1,e1), ident("true",e1), e1),call(rest,[ident("true",e1)],e1),toCps(e2, rest, exit)),e)), exit);
			case "&&":
				var id1 = "_r" + uid++;
				var id2 = "_r" + uid++;
				return toCps(e1, fun(id1, mk(EIf(binop("!=", ident(id1,e1), ident("true",e1), e1),call(rest,[ident("false",e1)],e1),toCps(e2, rest, exit)),e)), exit);
			default:
				var id1 = "_r" + uid++;
				var id2 = "_r" + uid++;
				return toCps(e1, fun(id1, toCps(e2, fun(id2, call(rest, [binop(op, ident(id1,e1), ident(id2,e2), e)], e)), exit)), exit);
			}
		case EIf(cond, e1, e2), ETernary(cond, e1, e2):
			return toCps(cond, fun("_c", mk(EIf(ident("_c",cond), toCps(e1, rest, exit), e2 == null ? retNull(rest) : toCps(e2, rest, exit)),e)), exit);
		case EWhile(cond, ewh):
			var id = ++uid;
			var loop = ident("_loop" + id, cond);
			var oldLoop = currentLoop, oldBreak = currentBreak;
			currentLoop = loop;
			currentBreak = function(e) return block([retNull(rest,e), mk(EReturn(),e)],e);
			var ewhile = block([
				fun("_r",
					toCps(cond, fun("_c", mk(EIf(ident("_c", cond), toCps(ewh, loop, exit), retNull(rest,cond)),cond)), exit)
				, "_loop"+id),
				retNull(loop, cond),
			],e);
			currentLoop = oldLoop;
			currentBreak = oldBreak;
			return ewhile;
		case EReturn(eret):
			return eret == null ? retNull(exit, e) : toCps(eret, exit, exit);
		case EObject(fields):
			var id = "_o" + uid++;
			var rest = call(rest, [ident(id,e)], e);
			fields.reverse();
			for( f in fields )
				rest = toCps(f.e, fun("_r", block([
					binop("=", mk(EField(ident(id,f.e), f.name),f.e), ident("_r",f.e), f.e),
					rest,
				],f.e)),exit);
			return block([
				mk(EVar(id, mk(EObject([]),e)),e),
				rest,
			],e);
		case EArrayDecl(el):
			var id = "_a" + uid++;
			var rest = call(rest, [ident(id,e)], e);
			var i = el.length - 1;
			while( i >= 0 ) {
				var e = el[i];
				rest = toCps(e, fun("_r", block([
					binop("=", mk(EArray(ident(id,e), mk(EConst(CInt(i)),e)),e), ident("_r",e), e),
					rest,
				],e)), exit);
				i--;
			}
			return block([
				mk(EVar(id, mk(EArrayDecl([]),e)),e),
				rest,
			],e);
		case EArray(earr, eindex):
			var id1 = "_r" + uid++;
			var id2 = "_r" + uid++;
			return toCps(earr, fun(id1, toCps(eindex, fun(id2, call(rest, [mk(EArray(ident(id1,e), ident(id2,e)),e)], e)), exit)), exit);
		case EVar(v, t, ev):
			if( ev == null )
				return block([e, retNull(rest, e)], e);
			return block([
				mk(EVar(v, t),e),
				toCps(ev, fun("_r", block([binop("=", ident(v,e), ident("_r",e), e), retNull(rest,e)], e)), exit),
			],e);
		case EConst(_), EIdent(_), EUnop(_), EField(_):
			return call(rest, [e], e);
		case ENew(cl, args):
			var names = [for( i in 0...args.length ) "_a"+uid++];
			var rargs = [for( i in 0...args.length ) ident(names[i], args[i])];
			var rest = call(rest,[mk(ENew(cl, rargs),e)],e);
			var i = args.length - 1;
			while( i >= 0 ) {
				rest = toCps(args[i], fun(names[i], rest), exit);
				i--;
			}
			return rest;
		case EBreak:
			if( currentBreak == null ) throw "Break outside loop";
			return currentBreak(e);
		case EContinue:
			if( currentLoop == null ) throw "Continue outside loop";
			return block([retNull(currentLoop, e), mk(EReturn(),e)], e);
		case ESwitch(v, cases, def):
			var cases = [for( c in cases ) { values : c.values, expr : toCps(c.expr, rest, exit) } ];
			return toCps(v, mk(EFunction([ { name : "_c", t : null } ], mk(ESwitch(ident("_c",v), cases, def == null ? retNull(rest) : toCps(def, rest, exit)),e)),e), exit );
		case EThrow(v):
			return toCps(v, mk(EFunction([ { name : "_v", t : null } ], mk(EThrow(v),v)), v), exit);
		case EMeta(name,_,e) if( name.charCodeAt(0) == ":".code ): // ignore custom ":" metadata
			return toCps(e, rest, exit);
		//case EDoWhile(_), ETry(_), ECall(_):
		default:
			throw "Unsupported async expression " + Printer.toString(e);
		}
	}

}


class AsyncInterp extends Interp {

	public function setContext( api : Dynamic ) {

		var funs = new Array();
		for( v in variables.keys() )
			if( Reflect.isFunction(variables.get(v)) )
				funs.push({ v : v, obj : null });

		variables.set("split", split);
		variables.set("makeIterator", makeIterator);

		var c = Type.getClass(api);
		for( f in (c == null ? Reflect.fields(api) : Type.getInstanceFields(c)) ) {
			var fv = Reflect.field(api, f);
			if( !Reflect.isFunction(fv) ) continue;
			if( f.charCodeAt(0) == "_".code ) f = f.substr(1);
			variables.set(f, fv);
			// create the async wrapper if doesn't exists
			if( f.substr(0, 2) != "a_" )
				funs.push({ v : f, obj : api });
		}

		for( v in funs ) {
			if( variables.exists("a_" + v.v) ) continue;
			var fv : Dynamic = variables.get(v.v);
			var obj = v.obj;
			variables.set("a_" + v.v, Reflect.makeVarArgs(function(args:Array<Dynamic>) {
				var onEnd = args.shift();
				onEnd(Reflect.callMethod(obj, fv, args));
			}));
		}
	}

	public function hasMethod( name : String ) {
		var v = variables.get(name);
		return v != null && Reflect.isFunction(v);
	}

	public function callValue( value : Dynamic, args : Array<Dynamic>, ?onResult : Dynamic -> Void, ?vthis : {} ) {
		var oldThis = variables.get("this");
		if( vthis != null )
			variables.set("this", vthis);
		if( onResult == null )
			onResult = function(_) {};
		args.unshift(onResult);
		Reflect.callMethod(null, value, args);
		variables.set("this", oldThis);
	}

	public function callAsync( id : String, args, ?onResult, ?vthis : {} ) {
		var v = variables.get(id);
		if( v == null )
			throw "Missing function " + id + "()";
		callValue(v, args, onResult, vthis);
	}

	function split( rest : Dynamic -> Void, args : Array<Dynamic> ) {
		if( args.length == 0 )
			rest(null);
		else {
			var count = args.length;
			function next(_) {
				if( --count == 0 ) rest(null);
			}
			for( a in args )
				a(next);
		}
	}

	override function fcall( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
		var m = Reflect.field(o, f);
		if( m == null ) {
			if( f.substr(0, 2) == "a_" ) {
				m = Reflect.field(o, f.substr(2));
				// fallback on sync version
				if( m != null ) {
					var onEnd = args.shift();
					onEnd(call(o, m, args));
					return null;
				}
				// fallback on generic script
				m = Reflect.field(o, "scriptCall");
				if( m != null ) {
					call(o, m, [args.shift(), f.substr(2), args]);
					return null;
				}
			} else {
				// fallback on generic script
				m = Reflect.field(o, "scriptCall");
				if( m != null ) {
					var result : Dynamic = null;
					call(o, m, [function(r) result = r, f, args]);
					return result;
				}
			}
			error(ECustom(o + " has no method " + f));
		}
		return call(o, m, args);
	}

}
