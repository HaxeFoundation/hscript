package hscript;

class JsInterp extends Interp {

	override function execute( expr : Expr ) : Dynamic {
		depth = 0;
		locals = new Map();
		var str = '({ _exec : ($$i) => ${exprValue(expr)} })';
		trace(str);
		var obj : Dynamic = js.Lib.eval(str);
		return obj._exec(this);
	}

	function escapeString(s:String) {
		return s.split("\\").join("\\\\").split("\r").join("\\r").split("\n").join("\\n").split('"').join('\\"');
	}

	function exprValue( expr : Expr ) {
		switch( Tools.expr(expr) ) {
		case EBlock([]):
			return "null";
		case EIf(cond,e1,e2):
			return exprJS(Tools.mk(ETernary(cond,e1,e2),expr));
		case EBlock(el):
			var el = el.copy();
			var last = el[el.length-1];
			el[el.length - 1] = Tools.mk(EReturn(last),last);
			var ebl = Tools.mk(EBlock(el),expr);
			return '(() => ${exprJS(ebl)})()'; // todo : return/break/continue inside expr here won't work !
		case ETry(e,v,t,ecatch):
			var expr = Tools.mk(ETry(Tools.mk(EReturn(e),e),v,t,Tools.mk(EReturn(ecatch),ecatch)),expr);
			return '(() => { ${exprJS(expr)} })()'; // todo : return/break/continue inside expr here won't work !
		case EVar(_,_,e):
			return e == null ? "null" : '(${exprValue(e)},null)';
		case EWhile(_), EFor(_), EDoWhile(_), EThrow(_):
			return '(() => {${exprJS(expr)}})()'; // todo : return/break/continue inside expr here won't work !
		case EMeta(_,_,e), ECheckType(e,_):
			return exprValue(e);
		default:
			return exprJS(expr);
		}
	}

	function exprBlock( expr : Expr ) {
		switch( Tools.expr(expr) ) {
		case EBlock(_):
			return exprJS(expr);
		default:
			return '{${exprJS(expr)};}';
		}
	}

	function addPos( estr : String ) {
		#if hscriptPos
		var expr = curExpr;
		var p = '{pmin:,pmax:,origin:"",line:}';
		return '($$i._p(${expr.pmin},${expr.pmax},${expr.origin},${expr.line}),$estr)';
		#else
		return estr;
		#end
	}

	function exprJS( expr : Expr ) : String {
		#if hscriptPos
		curExpr = e;
		var expr = expr.e;
		#end
		switch( expr ) {
		case EConst(c):
			return switch c {
			case CInt(v): Std.string(v);
			case CFloat(f): Std.string(f);
			case CString(s): '"'+escapeString(s)+'"';
			}
		case EIdent(v):
			if( locals.exists(v) )
				return v;
			switch( v ) {
			case "null", "true", "false": return v;
			default:
			}
			return '$$i.resolve("$v")';
		case EVar(n, t, e):
			locals.set(n, null);
			return e == null ? 'let $n' : 'let $n = ${exprValue(e)}';
		case EParent(e):
			return '(${exprValue(e)})';
		case EBlock(el):
			var old = locals.copy();
			var buf = new StringBuf();
			buf.add('{');
			for( e in el ) {
				buf.add(exprJS(e));
				buf.add(";");
			}
			buf.add('}');
			locals = old;
			return buf.toString();
		case EField(e, f):
			return '$$i.get(${exprValue(e)},"$f")';
		case EBinop(op, e1, e2):
			switch( op ) {
			case "+","-","*","/","%","&","|","^",">>","<<",">>>","==","!=",">=","<=",">","<":
				return '((${exprValue(e1)}) $op (${exprValue(e2)}))';
			case "||","&&":
				return '((${exprValue(e1)}) == true $op (${exprValue(e2)}) == true)';
			case "=":
				switch( Tools.expr(e1) ) {
				case EIdent(id) if( locals.exists(id) ):
					return id+" = "+exprValue(e2);
				case EIdent(id):
					return '$$i.setVar("$id",${exprValue(e2)})';
				case EField(e,f):
					return addPos('$$i.set(${exprValue(e)},"$f")');
				case EArray(e, index):
					return '$$i.setArray(${exprValue(e)},${exprValue(index)},${exprValue(e2)})';
				default:
					error(EInvalidOp("="));
				}
			case "+=","-=","*=","/=","%=","|=","&=","^=","<<=",">>=",">>>=":
				var aop = op.substr(0, op.length - 1);
				switch( Tools.expr(e1) ) {
				case EIdent(id) if( locals.exists(id) ):
					return id+" "+op+" "+exprValue(e2);
				case EIdent(id):
					return '$$i.setVar("$id",$$i.resolve("$id") $aop (${exprValue(e2)}))';
				case EField(e, f):
					return '(($$o,$$v) => $$i.set($$o,"$f",$$i.get($$o,"$f") $aop $$v)(${exprValue(e)},${exprValue(e2)})';
				case EArray(e, index):
					return '(($$a,$$idx,$$v) => $$i.setArray($$a,$$idx,$$i.getArray($$a,$$idx) $aop $$v))(${exprValue(e)},${exprValue(index)},${exprValue(e2)})';
				default:
					error(EInvalidOp(op));
				}
			case "...":
				return '$$i.intIterator(${exprValue(e1)},${exprValue(e2)})';
			case "is":
				return '$$i.isOfType(${exprValue(e1)},${exprValue(e2)})';
			default:
				error(EInvalidOp(op));
			}
		case EUnop(op, prefix, e):
			switch( op ) {
			case "!":
				return '${exprValue(e)} != true';
			case "-","~":
				return op+exprValue(e);
			case "++", "--":
				switch( Tools.expr(e) ) {
				case EIdent(id) if( locals.exists(id) ):
					return prefix ? op + id : id + op;
				case _ if( prefix ):
					var one = Tools.mk(EConst(CInt(1)),e);
					return exprJS(Tools.mk(EBinop(op.charAt(0)+"=",e,one),e));
				case EIdent(id):
					var op = op.charAt(1);
					return '(($$v) => ($$i.setVar("$id",$$v $op 1),$$v))($$i.resolve("$id"))';
				case EArray(e, index):
					var op = op.charAt(0);
					return '(($$a,$$idx) => { var $$v = $$i.getArray($$a,$$idx); $$i.setArray($$a,$$idx,$$v $op 1); return $$v; })(${exprValue(e)},${exprValue(index)})';
				case EField(e, f):
					return '(($$o) => { var $$v = $$i.get($$o,"$f"); $$i.set($$o,"$f",$$v $op 1); return $$v; })(${exprValue(e)})';
				default:
					error(EInvalidOp(op));
				}
			default:
				error(EInvalidOp(op));
			}
		case ECall(e, params):
			var args = [for( p in params ) exprValue(p)];
			switch( Tools.expr(e) ) {
			case EField(e,f):
				return addPos('$$i.fcall2(${exprValue(e)},"$f",[${args.join(',')}])');
			default:
				return '$$i.call(null,${exprValue(e)},[${args.join(',')}])';
			}
		case EIf(cond,e1,e2):
			return 'if( ${exprValue(cond)} == true ) ${exprJS(e1)}'+(e2 == null ? "" : 'else ${exprJS(e2)}');
		case ETernary(cond, e1, e2):
			return '((${exprValue(cond)} == true) ? ${exprValue(e1)} : ${exprValue(e2)})';
		case EWhile(cond, e):
			return 'while( ${exprValue(cond)} == true ) ${exprJS(e)}';
		case EFor(v, it, e):
			var prev = locals.exists(v);
			locals.set(v, null);
			var block = exprJS(e);
			if( !prev ) locals.remove(v);
			var iter = '$$i.makeIterator(${exprValue(it)})';
			return '{ var $$it = ${addPos(iter)}; while( $$it.hasNext() ) { var $v = $$it.next(); $block; } }';
		case EBreak:
			return 'break';
		case EContinue:
			return 'continue';
		case EReturn(null):
			return 'return';
		case EReturn(e):
			return 'return '+exprValue(e);
		case EArray(e, index):
			return '$$i.getArray(${exprValue(e)},${exprValue(index)})';
		case EArrayDecl(arr):
			if( arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _)) ) {
				var keys = [], values = [];
				for( e in arr ) {
					switch(Tools.expr(e)) {
					case EBinop("=>", eKey, eValue):
						keys.push(exprValue(eKey));
						values.push(exprValue(eValue));
					default:
						#if hscriptPos
						curExpr = e;
						#end
						error(ECustom("Invalid map key=>value expression"));
					}
				}
				return '$$i.makeMap([${keys.join(',')}],[${values.join(',')}])';
			}
			return '['+[for( e in arr ) exprValue(e)].join(',')+']';
		case ENew(cl, params):
			var args = [for( e in params ) exprValue(e)];
			return '$$i.cnew("$cl",[${args.join(',')}])';
		case EThrow(e):
			return "throw "+exprValue(e);
		case ETry(e, v, t, ecatch):
			var prev = locals.exists(v);
			locals.set(v, null);
			var ec = exprBlock(ecatch);
			if( !prev ) locals.remove(v);
			return 'try ${exprBlock(e)} catch( $v ) $ec';
		case EObject(fl):
			var fields = [for( f in fl ) f.name+":"+exprValue(f.e)];
			return '{${fields.join(',')}}'; // do not use 'set' here
		case EDoWhile(cond, e):
			return 'do ${exprBlock(e)} while( ${exprValue(cond)} == true )';
		case EMeta(_, _, e), ECheckType(e,_):
			return exprJS(e);
		case EFunction(args, e, name, ret):
			var prev = locals.copy();
			for( a in args )
				locals.set(a.name, null);
			var bl = exprBlock(e);
			locals = prev;
			var fname = if( name == null ) "" else { locals.set(name,null); " "+name; }
			return 'function$fname(${[for( a in args ) a.name].join(",")}) $bl';
		case ESwitch(e, cases, defaultExpr):
			var checks = [for( c in cases ) 'if( ${[for( v in c.values ) '$$v == ${exprValue(v)}'].join(" || ")} ) return ${exprValue(c.expr)};'];
			if( defaultExpr != null )
				checks.push('return '+exprValue(defaultExpr));
			return '(($$v) => { ${[for( c in checks ) c+";"].join(" ")} })(${exprValue(e)})';
		default:
			throw "TODO";
		}
	}

	function fcall2( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
		if( o == null ) {
			error(EInvalidAccess(f));
			return null;
		}
		return fcall(o,f,args);
	}

	function getArray( arr : Dynamic, index : Dynamic ) {
		return isMap(arr) ? getMapValue(arr,index) : arr[index];
	}

	function setArray( arr : Dynamic, index : Dynamic, v : Dynamic ) {
		if(isMap(arr) )
			setMapValue(arr, index, v);
		else
			arr[index] = v;
		return v;
	}

	function intIterator(v1,v2) {
		return new IntIterator(v1,v2);
	}

	function isOfType(v1,v2) {
		return Std.isOfType(v1,v2);
	}

	#if hscriptPos
	function _p( pmin, pmax, origin, line ) {
		curExpr = { expr : null, pmin : pmin, pmax: pmax, origin:origin, line:line };
	}
	#end

}