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
}

class Interp {

	public var variables : Hash<Dynamic>;
	var binops : Hash<Expr -> Expr -> Dynamic>;
	var declared : Array<{ n : String, old : Dynamic, exists : Bool }>;

	public function new() {
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
		case EIdent(id): variables.set(id,v);
		case EField(e,f): v = set(expr(e),f,v);
		default: throw Error.EInvalidOp("=");
		}
		return v;
	}

	function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		switch(e) {
		case EIdent(id):
			var v : Dynamic = variables.get(id);
			if( prefix ) {
				v += delta;
				variables.set(id,v);
			} else
				variables.set(id,v + delta);
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
		default:
			throw Error.EInvalidOp((delta > 0)?"++":"--");
		}
	}

	public function execute( program : Array<Expr> ) {
		return block(program);
	}

	function block( exprs : Array<Expr> ) {
		var old = declared;
		declared = new Array();
		var v = null;
		for( e in exprs )
			v = expr(e);
		for( d in declared )
			if( d.exists )
				variables.set(d.n,d.old);
			else
				variables.remove(d.n);
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
			var v = variables.get(id);
			if( v == null && !variables.exists(v) )
				throw Error.EUnknownVariable(id);
			return v;
		case EVar(n,e):
			declared.unshift({ n : n, old : variables.get(n), exists : variables.exists(n) });
			variables.set(n,(e == null)?null:expr(e));
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
		}
		return null;
	}

	function whileLoop(econd,e) {
		while( expr(econd) == true ) {
			try {
				block([e]);
			} catch( err : Stop ) {
				if( err == SBreak ) break;
			}
		}
	}

	function forLoop(v,it,e) {
		var old = if( variables.exists(v) ) { v : variables.get(v) } else null;
		var it : Dynamic = expr(it);
		if( it.iterator != null ) it = it.iterator();
		if( it.hasNext == null || it.next == null ) throw Error.EInvalidIterator(v);
		while( it.hasNext() ) {
			variables.set(v,it.next());
			try {
				block([e]);
			} catch( err : Stop ) {
				if( err == SBreak ) break;
			}
		}
		if( old == null )
			variables.remove(v)
		else
			variables.set(v,old.v);
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