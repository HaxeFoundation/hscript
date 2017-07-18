/*
 * Copyright (c) 2011, Nicolas Cannasse
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
import hscript.Expr.Error;
#if hscriptPos
import hscript.Expr.ErrorDef;
#end
import haxe.macro.Expr;

class Macro {

	var p : Position;
	#if haxe3
	var binops : Map<String,Binop>;
	var unops : Map<String,Unop>;
	#else
	var binops : Hash<Binop>;
	var unops : Hash<Unop>;
	#end

	public function new(pos) {
		p = pos;
		#if haxe3
		binops = new Map();
		unops = new Map();
		#else
		binops = new Hash();
		unops = new Hash();
		#end
		for( c in Type.getEnumConstructs(Binop) ) {
			if( c == "OpAssignOp" ) continue;
			var op = Type.createEnum(Binop, c);
			var assign = false;
			var str = switch( op ) {
			case OpAdd: assign = true;  "+";
			case OpMult: assign = true; "*";
			case OpDiv: assign = true; "/";
			case OpSub: assign = true; "-";
			case OpAssign: "=";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpAnd: assign = true; "&";
			case OpOr: assign = true; "|";
			case OpXor: assign = true; "^";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpShl: assign = true; "<<";
			case OpShr: assign = true; ">>";
			case OpUShr: assign = true; ">>>";
			case OpMod: assign = true; "%";
			case OpAssignOp(_): "";
			case OpInterval: "...";
			#if haxe3
			case OpArrow: "=>";
			#end
			};
			binops.set(str, op);
			if( assign )
				binops.set(str + "=", OpAssignOp(op));
		}
		for( c in Type.getEnumConstructs(Unop) ) {
			var op = Type.createEnum(Unop, c);
			var str = switch( op ) {
			case OpNot: "!";
			case OpNeg: "-";
			case OpNegBits: "~";
			case OpIncrement: "++";
			case OpDecrement: "--";
			}
			unops.set(str, op);
		}
	}

	#if !haxe3
	function isType(v:String) {
		var c0 = v.charCodeAt(0);
		return c0 >= 'A'.code && c0 <= 'Z'.code;
	}
	#end

	function map < T, R > ( a : Array<T>, f : T -> R ) : Array<R> {
		var b = new Array();
		for( x in a )
			b.push(f(x));
		return b;
	}

	function convertType( t : Expr.CType ) : ComplexType {
		return switch( t ) {
		case CTPath(pack, args):
			var params = [];
			if( args != null )
				for( t in args )
					params.push(TPType(convertType(t)));
			TPath({
				pack : pack,
				name : pack.pop(),
				params : params,
				sub : null,
			});
		case CTParent(t): TParent(convertType(t));
		case CTFun(args, ret):
			TFunction(map(args,convertType), convertType(ret));
		case CTAnon(fields):
			var tf = [];
			for( f in fields )
				tf.push( { name : f.name, meta : [], doc : null, access : [], kind : FVar(convertType(f.t),null), pos : p } );
			TAnonymous(tf);
		};
	}

	public function convert( e : hscript.Expr ) : Expr {
		return { expr : switch( #if hscriptPos e.e #else e #end ) {
			case EConst(c):
				EConst(switch(c) {
					case CInt(v): CInt(Std.string(v));
					case CFloat(f): CFloat(Std.string(f));
					case CString(s): CString(s);
					#if !haxe3
					case CInt32(v): CInt(Std.string(v));
					#end
				});
			case EIdent(v):
				#if !haxe3
				if( isType(v) )
					EConst(CType(v));
				else
				#end
					EConst(CIdent(v));
			case EVar(n, t, e):
				EVars([ { name : n, expr : if( e == null ) null else convert(e), type : if( t == null ) null else convertType(t) } ]);
			case EParent(e):
				EParenthesis(convert(e));
			case EBlock(el):
				EBlock(map(el,convert));
			case EField(e, f):
				#if !haxe3
				if( isType(f) )
					EType(convert(e), f);
				else
				#end
					EField(convert(e), f);
			case EBinop(op, e1, e2):
				var b = binops.get(op);
				if( b == null ) throw EInvalidOp(op);
				EBinop(b, convert(e1), convert(e2));
			case EUnop(op, prefix, e):
				var u = unops.get(op);
				if( u == null ) throw EInvalidOp(op);
				EUnop(u, !prefix, convert(e));
			case ECall(e, params):
				ECall(convert(e), map(params, convert));
			case EIf(c, e1, e2):
				EIf(convert(c), convert(e1), e2 == null ? null : convert(e2));
			case EWhile(c, e):
				EWhile(convert(c), convert(e), true);
			case EDoWhile(c, e):
				EWhile(convert(c), convert(e), false);
			#if (haxe_211 || haxe3)
			case EFor(v, it, efor):
				var p = #if hscriptPos { file : p.file, min : e.pmin, max : e.pmax } #else p #end;
				EFor({ expr : EIn({ expr : EConst(CIdent(v)), pos : p },convert(it)), pos : p }, convert(efor));
			#else
			case EFor(v, it, e):
				EFor(v, convert(it), convert(e));
			#end
			case EBreak:
				EBreak;
			case EContinue:
				EContinue;
			case EFunction(args, e, name, ret):
				var targs = [];
				for( a in args )
					targs.push( {
						name : a.name,
						type : a.t == null ? null : convertType(a.t),
						opt : false,
						value : null,
					});
				EFunction(name, {
					params : [],
					args : targs,
					expr : convert(e),
					ret : ret == null ? null : convertType(ret),
				});
			case EReturn(e):
				EReturn(e == null ? null : convert(e));
			case EArray(e, index):
				EArray(convert(e), convert(index));
			case EArrayDecl(el):
				EArrayDecl(map(el,convert));
			case ENew(cl, params):
				var pack = cl.split(".");
				ENew( { pack : pack, name : pack.pop(), params : [], sub : null }, map(params, convert));
			case EThrow(e):
				EThrow(convert(e));
			case ETry(e, v, t, ec):
				ETry(convert(e), [ { type : convertType(t), name : v, expr : convert(ec) } ]);
			case EObject(fields):
				var tf = [];
				for( f in fields )
					tf.push( { field : f.name, expr : convert(f.e) } );
				EObjectDecl(tf);
			case ETernary(cond, e1, e2):
				ETernary(convert(cond), convert(e1), convert(e2));
			case ESwitch(e, cases, edef):
				ESwitch(convert(e), [for( c in cases ) { values : [for( v in c.values ) convert(v)], expr : convert(c.expr) } ], edef == null ? null : convert(edef));
			case EMeta(m, params, esub):
				var mpos = #if hscriptPos { file : p.file, min : e.pmin, max : e.pmax } #else p #end;
				EMeta({ name : m, params : params == null ? [] : [for( p in params ) convert(p)], pos : mpos }, convert(esub));
		}, pos : #if hscriptPos { file : p.file, min : e.pmin, max : e.pmax } #else p #end }
	}

}
