/*
 * Copyright (c) 2008, Nicolas Cannasse
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
package hscript;
import hscript.Expr;

private enum Stop {
	SBreak;
	SContinue;
	SReturn( v : Dynamic );
}

class Interp {

	public var variables : Hash<Dynamic>;
	var locals : Hash<{ r : Dynamic }>;
	var binops : Hash<Expr -> Expr -> Dynamic>;
	var declared : Array<{ n : String, old : { r : Dynamic } }>;

	public function new() {
		locals = new Hash();
		variables = new Hash();
		variables.set("null",null);
		variables.set("true",true);
		variables.set("false",false);
		initOps();
	}

	function initOps() {
		var me = this;
		binops = new Hash();
		binops.set("+",function(e1,e2) return me.expr(e1) + me.expr(e2));
		binops.set("-",function(e1,e2) return me.expr(e1) - me.expr(e2));
		binops.set("*",function(e1,e2) return me.expr(e1) * me.expr(e2));
		binops.set("/",function(e1,e2) return me.expr(e1) / me.expr(e2));
		binops.set("%",function(e1,e2) return me.expr(e1) % me.expr(e2));
		binops.set("&",function(e1,e2) return me.expr(e1) & me.expr(e2));
		binops.set("|",function(e1,e2) return me.expr(e1) | me.expr(e2));
		binops.set("^",function(e1,e2) return me.expr(e1) ^ me.expr(e2));
		binops.set("<<",function(e1,e2) return me.expr(e1) << me.expr(e2));
		binops.set(">>",function(e1,e2) return me.expr(e1) >> me.expr(e2));
		binops.set(">>>",function(e1,e2) return me.expr(e1) >>> me.expr(e2));
		binops.set("==",function(e1,e2) return me.expr(e1) == me.expr(e2));
		binops.set("!=",function(e1,e2) return me.expr(e1) != me.expr(e2));
		binops.set(">=",function(e1,e2) return me.expr(e1) >= me.expr(e2));
		binops.set("<=",function(e1,e2) return me.expr(e1) <= me.expr(e2));
		binops.set(">",function(e1,e2) return me.expr(e1) > me.expr(e2));
		binops.set("<",function(e1,e2) return me.expr(e1) < me.expr(e2));
		binops.set("||",function(e1,e2) return me.expr(e1) == true || me.expr(e2) == true);
		binops.set("&&",function(e1,e2) return me.expr(e1) == true && me.expr(e2) == true);
		binops.set("=",assign);
	}

	function assign( e1 : Expr, e2 : Expr ) {
		var v = expr(e2);
		switch( e1 ) {
		case EIdent(id):
			var l = locals.get(id);
			if( l == null )
				variables.set(id,v)
			else
				l.r = v;
		case EField(e,f):
			v = set(expr(e),f,v);
		case EArray(e,index):
			expr(e)[expr(index)] = v;
		default: throw Error.EInvalidOp("=");
		}
		return v;
	}

	function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		switch(e) {
		case EIdent(id):
			var l = locals.get(id);
			var v : Dynamic = (l == null) ? variables.get(id) : l.r;
			if( prefix ) {
				v += delta;
				if( l == null ) variables.set(id,v) else l.r = v;
			} else
				if( l == null ) variables.set(id,v + delta) else l.r = v + delta;
			return v;
		case EField(e,f):
			var obj = expr(e);
			var v : Dynamic = get(obj,f);
			if( prefix ) {
				v += delta;
				set(obj,f,v);
			} else
				set(obj,f,v + delta);
			return v;
		case EArray(e,index):
			var arr = expr(e);
			var index = expr(index);
			var v = arr[index];
			if( prefix ) {
				v += delta;
				arr[index] = v;
			} else
				arr[index] = v + delta;
			return v;
		default:
			throw Error.EInvalidOp((delta > 0)?"++":"--");
		}
	}

	public function execute( expr : Expr ) {
		locals = new Hash();
		return exprReturn(expr);
	}

	function exprReturn(e) : Dynamic {
		try {
			return expr(e);
		} catch( e : Stop ) {
			switch( e ) {
			case SBreak: throw "Invalid break";
			case SContinue: throw "Invalid continue";
			case SReturn(v): return v;
			}
		}
		return null;
	}

	function duplicate<T>( h : Hash<T> ) {
		var h2 = new Hash();
		for( k in h.keys() )
			h2.set(k,h.get(k));
		return h2;
	}

	function block( exprs : Array<Expr> ) {
		var old = declared;
		declared = new Array();
		var v = null;
		for( e in exprs )
			v = expr(e);
		for( d in declared )
			locals.set(d.n,d.old);
		declared = old;
		return v;
	}

	public function expr( e : Expr ) : Dynamic {
		switch( e ) {
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			}
		case EIdent(id):
			var l = locals.get(id);
			if( l != null )
				return l.r;
			var v = variables.get(id);
			if( v == null && !variables.exists(v) )
				throw Error.EUnknownVariable(id);
			return v;
		case EVar(n,e):
			declared.unshift({ n : n, old : locals.get(n) });
			locals.set(n,{ r : (e == null)?null:expr(e) });
			return null;
		case EParent(e):
			return expr(e);
		case EBlock(exprs):
			return block(exprs);
		case EField(e,f):
			return get(expr(e),f);
		case EBinop(op,e1,e2):
			var fop = binops.get(op);
			if( fop == null ) throw Error.EInvalidOp(op);
			return fop(e1,e2);
		case EUnop(op,prefix,e):
			switch(op) {
			case "!":
				return expr(e) != true;
			case "-":
				return -expr(e);
			case "++":
				return increment(e,prefix,1);
			case "--":
				return increment(e,prefix,-1);
			default:
				throw Error.EInvalidOp(op);
			}
		case ECall(e,params):
			var args = new Array();
			for( p in params )
				args.push(expr(p));
			switch(e) {
			case EField(e,f):
				var obj = expr(e);
				return call(obj,Reflect.field(obj,f),args);
			default:
				return call(null,expr(e),args);
			}
		case EIf(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else if( e2 == null ) null else expr(e2);
		case EWhile(econd,e):
			whileLoop(econd,e);
			return null;
		case EFor(v,it,e):
			forLoop(v,it,e);
			return null;
		case EBreak:
			throw SBreak;
		case EContinue:
			throw SContinue;
		case EReturn(e):
			throw SReturn((e == null)?null:expr(e));
		case EFunction(params,fexpr,name):
			var capturedLocals = duplicate(locals);
			var me = this;
			var f = function(args:Array<Dynamic>) {
				if( args.length != params.length ) throw "Invalid number of parameters";
				var old = me.locals;
				me.locals = me.duplicate(capturedLocals);
				for( i in 0...params.length )
					me.locals.set(params[i],{ r : args[i] });
				var r = me.exprReturn(fexpr);
				me.locals = old;
				return r;
			};
			var f = Reflect.makeVarArgs(f);
			if( name != null )
				variables.set(name,f);
			return f;
		case EArrayDecl(arr):
			var a = new Array();
			for( e in arr )
				a.push(expr(e));
			return a;
		case EArray(e,index):
			return expr(e)[expr(index)];
		}
		return null;
	}

	function whileLoop(econd,e) {
		while( expr(econd) == true ) {
			try {
				block([e]);
			} catch( err : Stop ) {
				switch(err) {
				case SContinue:
				case SBreak: break;
				case SReturn(_): throw err;
				}
			}
		}
	}

	function forLoop(v,it,e) {
		var old = locals.get(v);
		var it : Dynamic = expr(it);
		if( it.iterator != null ) it = it.iterator();
		if( it.hasNext == null || it.next == null ) throw Error.EInvalidIterator(v);
		while( it.hasNext() ) {
			locals.set(v,{ r : it.next() });
			try {
				block([e]);
			} catch( err : Stop ) {
				switch( err ) {
				case SContinue:
				case SBreak: break;
				case SReturn(_): throw err;
				}
			}
		}
		locals.set(v,old);
	}

	function get( o : Dynamic, f : String ) {
		return Reflect.field(o,f);
	}

	function set( o : Dynamic, f : String, v : Dynamic ) {
		Reflect.setField(o,f,v);
		return v;
	}

	function call( o : Dynamic, f : Dynamic, args : Array<Dynamic> ) {
		return Reflect.callMethod(o,f,args);
	}

}