package hscript;

class JsInterp extends Interp {

	/**
		Variables declared in `ctx` are directly accessed without going through the `variables` map, which is faster
	**/
	public var ctx : {};

	/**
		If properties are defined, all calls to get/set are only done for fields accesses which are listed here.
	**/
	public var properties : Map<String,Bool>;


	var localNames : Map<String,String>;

	override function execute( expr : Expr ) : Dynamic {
		depth = 0;
		localNames = new Map();
		var str = '(($$i) => ${exprValue(expr)})';
		var f : Dynamic -> Dynamic = js.Lib.eval(str);
		return f(this);
	}

	function escapeString(s:String) {
		return s.split("\\").join("\\\\").split("\r").join("\\r").split("\n").join("\\n").split('"').join('\\"');
	}

	function handleRBC( e : Expr ) {
		// todo : return/break/continue inside expr here won't work !
		return e;
	}

	function exprValue( expr : Expr ) {
		switch( Tools.expr(expr) ) {
		case EBlock([]):
			return "null";
		case EIf(cond,e1,e2):
			return exprJS(Tools.mk(ETernary(cond,e1,e2),expr));
		case EBlock(el):
			var el = [for( e in el ) handleRBC(e)];
			var last = el[el.length-1];
			switch( Tools.expr(last) ) {
			case EFunction(_,_,name,_) if( name != null ): // don't return latest named function
			default:
				el[el.length - 1] = Tools.mk(EReturn(last),last);
			}
			var ebl = Tools.mk(EBlock(el),expr);
			return '(() => ${exprJS(ebl)})()';
		case ETry(e,v,t,ecatch):
			e = handleRBC(e);
			ecatch = handleRBC(ecatch);
			var expr = Tools.mk(ETry(Tools.mk(EReturn(e),e),v,t,Tools.mk(EReturn(ecatch),ecatch)),expr);
			return '(() => { ${exprJS(expr)} })()';
		case EVar(_,_,e):
			return e == null ? "null" : '(${exprValue(e)},null)';
		case EWhile(_), EFor(_), EDoWhile(_), EThrow(_):
			expr = handleRBC(expr);
			return '(() => {${exprJS(expr)}})()';
		case EMeta(_,_,e), ECheckType(e,_):
			return exprValue(e);
		case EFunction(_,_,name,_) if( name != null ):
			return '(() => {${exprJS(expr)}})()';
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
		return '($$i._p(${expr.pmin},${expr.pmax},"${expr.origin}",${expr.line}),$estr)';
		#else
		return estr;
		#end
	}

	function isContext(v:String) {
		return ctx != null && Reflect.hasField(ctx,v);
	}

	function isProperty(f:String) {
		return properties == null || properties.get(f);
	}

	function exprCond( e : Expr ) {
		return switch( Tools.expr(e) ) {
		case EBinop("=="|"!="|">="|">"|"<="|"<"|"&&"|"||",_): exprValue(e);
		default: '(${exprOp(e)} == true)';
		}
	}

	function exprOp( e : Expr ) {
		return switch( Tools.expr(e) ) {
		case EBinop(_), EUnop(_): '(${exprValue(e)})';
		default: exprValue(e);
		}
	}

	function declLocal( n : String ) {
		if( !localNames.exists(n) ) {
			localNames.set(n, n);
			return n;
		}
		var c = 2;
		while( localNames.exists(n+c) ) c++;
		localNames.set(n, n+c);
		return n+c;
	}

	function exprJS( expr : Expr ) : String {
		#if hscriptPos
		curExpr = expr;
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
			var v2 = localNames.get(v);
			if( v2 != null )
				return v2;
			if( isContext(v) )
				return '$$i.ctx.$v';
			switch( v ) {
			case "null", "true", "false": return v;
			default:
			}
			return '$$i.resolve("$v")';
		case EVar(n, t, e):
			n = declLocal(n);
			return e == null ? 'let $n' : 'let $n = ${exprValue(e)}';
		case EParent(e):
			return '(${exprValue(e)})';
		case EBlock(el):
			var old = localNames.copy();
			// pre define name functions
			for( e in el )
				switch( Tools.expr(e) ) {
				case EFunction(_,_,name,_): declLocal(name);
				default:
				}
			var buf = new StringBuf();
			buf.add('{');
			for( e in el ) {
				buf.add(exprJS(e));
				buf.add(";");
			}
			buf.add('}');
			localNames = old;
			return buf.toString();
		case EField(e,f) if( !isProperty(f) ):
			return exprValue(e)+"."+f;
		case EField(e, f):
			return '$$i.get(${exprValue(e)},"$f")';
		case EBinop(op, e1, e2):
			switch( op ) {
			case "+","-","*","/","%","&","|","^",">>","<<",">>>","==","!=",">=","<=",">","<":
				return '${exprOp(e1)} $op ${exprOp(e2)}';
			case "||","&&":
				return '(${exprCond(e1)} $op ${exprCond(e2)})';
			case "=":
				switch( Tools.expr(e1) ) {
				case EIdent(id) if( localNames.exists(id) ):
					return localNames.get(id)+" = "+exprValue(e2);
				case EIdent(id) if( isContext(id) ):
					return '$$i.ctx.$id = ${exprValue(e2)}';
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
				case EIdent(id) if( localNames.exists(id) ):
					return localNames.get(id)+" "+op+" "+exprValue(e2);
				case EIdent(id) if( isContext(id) ):
					return '$$i.ctx.$id $op ${exprValue(e2)}';
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
				return op+exprOp(e);
			case "++", "--":
				switch( Tools.expr(e) ) {
				case EIdent(id) if( localNames.exists(id) ):
					id = localNames.get(id);
					return prefix ? op + id : id + op;
				case EIdent(id) if( isContext(id) ):
					return prefix ? op + "$i.ctx."+id : "$i.ctx."+id + op;
				case _ if( prefix ):
					var one = Tools.mk(EConst(CInt(1)),e);
					return exprJS(Tools.mk(EBinop(op.charAt(0)+"=",e,one),e));
				case EIdent(id):
					var op = op.charAt(1);
					return '(($$v) => ($$i.setVar("$id",$$v $op 1),$$v))($$i.resolve("$id"))';
				case EArray(e, index):
					var op = op.charAt(0);
					var v = declLocal("$v");
					var str = '(($$a,$$idx) => { let $v = $$i.getArray($$a,$$idx); $$i.setArray($$a,$$idx,$v $op 1); return $v; })(${exprValue(e)},${exprValue(index)})';
					localNames.remove(v);
					return str;
				case EField(e, f):
					var v = declLocal("$v");
					var str = '(($$o) => { let $v = $$i.get($$o,"$f"); $$i.set($$o,"$f",$$v $op 1); return $v; })(${exprValue(e)})';
					localNames.remove(v);
					return str;
				default:
					error(EInvalidOp(op));
				}
			default:
				error(EInvalidOp(op));
			}
		case ECall(e, params):
			var args = [for( p in params ) exprValue(p)];
			switch( Tools.expr(e) ) {
			case EField(eobj,f):
				var isCtx = false;
				var obj = eobj;
				while( true ) {
					switch( Tools.expr(obj) ) {
					case EField(o,_): obj = o;
					case EIdent(i) if( isContext(i) ): isCtx = true; break;
					default: break;
					}
				}
				if( isCtx )
					return '${exprValue(e)}(${args.join(',')})';
				return addPos('$$i.fcall2(${exprValue(eobj)},"$f",[${args.join(',')}])');
			case EIdent(id) if( localNames.exists(id) ):
				id = localNames.get(id);
				return '$id(${args.join(',')})';
			case EIdent(id) if( isContext(id) ):
				return '$$i.ctx.$id(${args.join(',')})';
			default:
				return '$$i.call(null,${exprValue(e)},[${args.join(',')}])';
			}
		case EIf(cond,e1,e2):
			return 'if( ${exprCond(cond)} ) ${exprJS(e1)}'+(e2 == null ? "" : 'else ${exprJS(e2)}');
		case ETernary(cond, e1, e2):
			return '(${exprCond(cond)} ? ${exprValue(e1)} : ${exprValue(e2)})';
		case EWhile(cond, e):
			return 'while( ${exprValue(cond)} ) ${exprJS(e)}';
		case EFor(v, it, e):
			v = declLocal(v);
			var block = exprJS(e);
			localNames.remove(v);
			var iter = '$$i.makeIterator(${exprValue(it)})';
			var it = declLocal("$it");
			var str = '{ let $it = ${addPos(iter)}; while( $it.hasNext() ) { let $v = $it.next(); $block; } }';
			localNames.remove(it);
			return str;
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
			v = declLocal(v);
			var ec = exprBlock(ecatch);
			localNames.remove(v);
			return 'try ${exprBlock(e)} catch( $v ) $ec';
		case EObject(fl):
			var fields = [for( f in fl ) f.name+":"+exprValue(f.e)];
			return '{${fields.join(',')}}'; // do not use 'set' here
		case EDoWhile(cond, e):
			return 'do ${exprBlock(e)} while( ${exprCond(cond)} )';
		case EMeta(_, _, e), ECheckType(e,_):
			return exprJS(e);
		case EFunction(args, e, name, ret):
			var prev = localNames.copy();
			if( name != null && !localNames.exists(name) )
				declLocal(name);
			for( a in args )
				localNames.set(a.name, a.name);
			var bl = exprBlock(e);
			localNames = prev;
			var fstr = 'function(${[for( a in args ) a.name].join(",")}) $bl';
			if( name != null )
				fstr = 'let $name = $$i.setVar("$name",$fstr)';
			return fstr;
		case ESwitch(e, cases, defaultExpr):
			var checks = [for( c in cases ) 'if( ${[for( v in c.values ) '$$v == ${exprValue(v)}'].join(" || ")} ) return ${exprValue(handleRBC(c.expr))};'];
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
		curExpr = { e : null, pmin : pmin, pmax: pmax, origin:origin, line:line };
	}
	#end

}