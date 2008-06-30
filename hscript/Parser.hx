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

enum Token {
	TEof;
	TConst( c : Const );
	TId( s : String );
	TOp( s : String );
	TPOpen;
	TPClose;
	TBrOpen;
	TBrClose;
	TDot;
	TComma;
	TSemicolon;
}

class Parser {

	// config / variables
	public var line : Int;
	public var opChars : String;
	public var identChars : String;
	public var opPriority : Array<String>;
	public var unopsPrefix : Array<String>;
	public var unopsSuffix : Array<String>;

	// implementation
	var char : Null<Int>;
	var ops : Array<Bool>;
	var idents : Array<Bool>;
	var tokens : haxe.FastList<Token>;

	public function new() {
		line = 1;
		opChars = "+*/-=!><&|^%";
		identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
		opPriority = [
			"=",
			"||","&&",
			"==","!=",">","<",">=","<=",
			"|","&","^",
			"<<",">>",">>>",
			"+","-",
			"*","/",
			"%"
		];
		unopsPrefix = ["!","++","--","-"];
		unopsSuffix = ["++","--"];
	}

	public function parseString( s : String ) {
		return parse( new haxe.io.StringInput(s) );
	}

	public function parse( s : haxe.io.Input ) {
		char = null;
		ops = new Array();
		idents = new Array();
		tokens = new haxe.FastList<Token>();
		for( i in 0...opChars.length )
			ops[opChars.charCodeAt(i)] = true;
		for( i in 0...identChars.length )
			idents[identChars.charCodeAt(i)] = true;
		var a = new Array();
		while( true ) {
			var tk = token(s);
			if( tk == TEof ) break;
			tokens.add(tk);
			a.push(parseFullExpr(s));
		}
		return a;
	}

	function unexpected( tk ) : Dynamic {
		throw Error.EUnexpected(tokenString(tk));
		return null;
	}

	function parseFullExpr(s) {
		var e = parseExpr(s);
		var tk = token(s);
		if( tk != TSemicolon && tk != TEof )
			switch( e ) {
			case EBlock(_): tokens.add(tk);
			default: unexpected(tk);
			}
		return e;
	}

	function parseExpr( s : haxe.io.Input ) {
		var tk = token(s);
		switch( tk ) {
		case TId(id):
			var e = parseStructure(s,id);
			if( e == null )
				return parseExprNext(s,EIdent(id));
			return e;
		case TConst(c):
			return parseExprNext(s,EConst(c));
		case TPOpen:
			var e = parseExpr(s);
			tk = token(s);
			if( tk != TPClose ) unexpected(tk);
			return parseExprNext(s,EParent(e));
		case TBrOpen:
			var a = new Array();
			while( true ) {
				tk = token(s);
				if( tk == TBrClose )
					break;
				tokens.add(tk);
				a.push(parseFullExpr(s));
			}
			return EBlock(a);
		case TOp(op):
			var found;
			for( x in unopsPrefix )
				if( x == op )
					return EUnop(op,true,parseExpr(s));
			return unexpected(tk);
		default:
			return unexpected(tk);
		}
	}

	function parseStructure( s, id ) {
		return switch( id ) {
		case "if":
			var cond = parseExpr(s);
			var e1 = parseExpr(s);
			var e2 = null;
			var semic = false;
			var tk = token(s);
			if( tk == TSemicolon ) {
				semic = true;
				tk = token(s);
			}
			if( Type.enumEq(tk,TId("else")) )
				e2 = parseExpr(s);
			else {
				tokens.add(tk);
				if( semic ) tokens.add(TSemicolon);
			}
			EIf(cond,e1,e2);
		case "var":
			var tk = token(s);
			var ident;
			switch(tk) {
			case TId(id): ident = id;
			default: unexpected(tk);
			}
			tk = token(s);
			var e;
			if( Type.enumEq(tk,TOp("=")) )
				e = parseExpr(s);
			else
				tokens.add(tk);
			EVar(ident,e);
		case "while":
			var econd = parseExpr(s);
			var e = parseExpr(s);
			EWhile(econd,e);
		case "for":
			var tk = token(s);
			if( tk != TPOpen ) unexpected(tk);
			tk = token(s);
			var vname;
			switch( tk ) {
			case TId(id): vname = id;
			default: unexpected(tk);
			}
			tk = token(s);
			if( !Type.enumEq(tk,TId("in")) ) unexpected(tk);
			var eiter = parseExpr(s);
			tk = token(s);
			if( tk != TPClose ) unexpected(tk);
			EFor(vname,eiter,parseExpr(s));
		case "break": EBreak;
		case "continue": EContinue;
		case "else": unexpected(TId(id));
		default: null;
		}
	}

	function priority(op) {
		for( i in 0...opPriority.length )
			if( opPriority[i] == op )
				return i;
		return -1;
	}

	function parseExprNext( s : haxe.io.Input, e1 : Expr ) {
		var tk = token(s);
		switch( tk ) {
		case TOp(op):
			for( x in unopsSuffix )
				if( x == op )
					return EUnop(op,false,e1);
			var e2 = parseExpr(s);
			switch( e2 ) {
			case EBinop(op2,e2,e3):
				if( priority(op) > priority(op2) )
					return EBinop(op2,EBinop(op,e1,e2),e3);
			default:
			}
			return EBinop(op,e1,e2);
		case TDot:
			tk = token(s);
			var field;
			switch(tk) {
			case TId(id): field = id;
			default: unexpected(tk);
			}
			return parseExprNext(s,EField(e1,field));
		case TPOpen:
			var args = new Array();
			tk = token(s);
			if( tk != TPClose ) {
				tokens.add(tk);
				while( true ) {
					args.push(parseExpr(s));
					tk = token(s);
					switch( tk ) {
					case TComma:
					case TPClose: break;
					default: unexpected(tk);
					}
				}
			}
			return ECall(e1,args);
		default:
			tokens.add(tk);
			return e1;
		}
	}

	function readChar( s : haxe.io.Input ) {
		return try s.readByte() catch( e : Dynamic ) 0;
	}

	function readString( s : haxe.io.Input, until ) {
		var c;
		var b = new StringBuf();
		var esc = false;
		while( true ) {
			try {
				c = s.readByte();
			} catch( e : Dynamic ) {
				throw Error.EUnterminatedString;
			}
			if( esc ) {
				esc = false;
				switch( c ) {
				case 110: b.addChar(10); // \n
				case 114: b.addChar(13); // \r
				case 116: b.addChar(9); // \t
				case 39: b.addChar(39); // \'
				case 34: b.addChar(34); // \"
				case 92: b.addChar(92); // \\
				default: throw Error.EInvalidChar(c);
				}
			} else if( c == 92 )
				esc = true;
			else if( c == until )
				break;
			else
				b.addChar(c);
		}
		return b.toString();
	}

	function token( s : haxe.io.Input ) {
		if( !tokens.isEmpty() )
			return tokens.pop();
		var char;
		if( this.char == null )
			char = readChar(s);
		else {
			char = this.char;
			this.char = null;
		}
		while( true ) {
			switch( char ) {
			case 0: return TEof;
			case 32,9,13: // space, tab, CR
			case 10: line++; // LF
			case 48,49,50,51,52,53,54,55,56,57: // 0...9
				var n = char - 48;
				var exp = 0;
				while( true ) {
					char = readChar(s);
					exp *= 10;
					switch( char ) {
					case 48,49,50,51,52,53,54,55,56,57:
						n = n * 10 + (char - 48);
					case 46:
						if( exp > 0 )
							throw Error.EInvalidChar(char);
						exp = 1;
					default:
						this.char = char;
						return TConst( (exp > 0) ? CFloat(n * 10 / exp) : CInt(n) );
					}
				}
			case 59: return TSemicolon;
			case 40: return TPOpen;
			case 41: return TPClose;
			case 44: return TComma;
			case 46: return TDot;
			case 123: return TBrOpen;
			case 125: return TBrClose;
			case 39: return TConst( CString(readString(s,39)) );
			case 34: return TConst( CString(readString(s,34)) );
			default:
				if( ops[char] ) {
					var op = Std.chr(char);
					while( true ) {
						char = readChar(s);
						if( !ops[char] ) {
							this.char = char;
							return TOp(op);
						}
						op += Std.chr(char);
					}
				}
				if( idents[char] ) {
					var id = Std.chr(char);
					while( true ) {
						char = readChar(s);
						if( !idents[char] ) {
							this.char = char;
							return TId(id);
						}
						id += Std.chr(char);
					}
				}
				throw Error.EInvalidChar(char);
			}
			char = readChar(s);
		}
		return null;
	}

	function constString( c ) {
		return switch(c) {
		case CInt(v): Std.string(v);
		case CFloat(f): Std.string(f);
		case CString(s): s; // TODO : escape + quote
		}
	}

	function tokenString( t ) {
		return switch( t ) {
		case TEof: "<eof>";
		case TConst(c): constString(c);
		case TId(s): s;
		case TOp(s): s;
		case TPOpen: "(";
		case TPClose: ")";
		case TBrOpen: "{";
		case TBrClose: "}";
		case TDot: ".";
		case TComma: ",";
		case TSemicolon: ";";
		}
	}

}
