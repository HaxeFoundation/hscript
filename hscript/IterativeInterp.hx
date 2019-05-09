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

import hscript.Expr.Expr;

import hscript.Tools;
import hscript.Expr;
import hscript.Interp;


/**
 * Takes a regular hscript EBlock expression and executes it line-by-line
 * @author Elliott Smith
 */
class IterativeInterp extends Interp
{
	var _on_complete:Dynamic->Void;
	var frame_stack:Array<StackFrame>;
	var current_frame:StackFrame;
	var script_complete:Bool;
	var yield:Bool = false;
	
	/**
	   Initialize this interp instance with a script to step through.
	   @param	e - an Expr - ideally one containing at least one EBlock.
	   @param	on_complete - a Dynamic->Void which will be called with the Expr's return value should the Expr return.
	**/
	public function prepareScript(e:Expr, ?on_complete:Dynamic->Void):Void{
		depth = 0;
		locals = new Map();
		declared = [];
		if (on_complete != null){
			_on_complete = on_complete;
		}
		var me = this;
		variables.set("__intern_reset_pc", function(){
			me.current_frame.pc = 0;
			#if hs_verbose
			trace("Resetting block: " + me.current_frame);
			#end
		});
		variables.set("__intern_yield", function(){
			me.yield = true;
			#if hs_verbose
			trace("Yield called by user-space script in frame:" +me.current_frame);
			#end
		});
		frame_stack = [];
		script_complete = false;
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch(e){
			case EBlock(a):
				current_frame = new StackFrame(a, CSBlock);
			case EWhile(econd, eb):
				var a:Array<Expr>;
				switch(Tools.expr(eb)){
					case EBlock(ea):
						a = ea;
					default:
						a = [eb];
				}
				current_frame = new StackFrame(a, CSWhile(econd));
			case EDoWhile(econd, eb):
				var a:Array<Expr>;
				switch(Tools.expr(eb)){
					case EBlock(ea):
						a = ea;
					default:
						a = [eb];
				}
				current_frame = new StackFrame(a, CSDoWhile(econd));
			default:
				current_frame = new StackFrame([curExprOr(e)], CSBlock);
		}
		locals = current_frame.locals;
	}
	
	private inline function curExprOr(e:#if hscriptPos ExprDef #else Expr #end):Expr{
		#if hscriptPos
		return curExpr;
		#else
		return e;
		#end
	}
	
	private function pushFrame(block:StackFrame){
		frame_stack.push(current_frame);
		current_frame = block;
		locals = current_frame.locals;
	}
	
	private function popFrame(){
		current_frame = frame_stack.pop();
		current_frame.call_count = 0;
		if (current_frame.called){
			current_frame.pc --;
		}
		locals = current_frame.locals;
	}
	
	/**
	   Iterate through the previously-supplied script. Will stop early if the script completes or a yield is called in user-space
	   @param	steps	The number of instructions to step through
	**/
	public function stepScript(steps:Int = 1):Void{
		yield = false;
		while (!yield && !script_complete && steps > 0){
			steps--;
			var e:Expr = current_frame.block[current_frame.pc];
			if (e == null){
				
				script_complete = true;
				_on_complete("Script error: "+current_frame);
				return;
			}
			current_frame.pc++;
			if (current_frame.called){
				current_frame.called = false;
			}
			else{
				current_frame.call_results = [];
			}
			
			current_frame.call_count = 0;
			
			#if hs_verbose
			for(b in frame_stack){
				trace(b);
			}
			trace(current_frame);
			trace(e);
			#end
			try{
				expr(e);
			}
			catch (s:Stop){
				switch(s){
					case SContinue:
						while (true){
							switch(current_frame.control){
								case CSWhile(condition), CSDoWhile(condition):
									break;
								case CSFor(name, iter):
									break;
								default:
									popFrame();
									if (current_frame == null){
										trace("Invalid continue.");
										return;
									}
							}
						}
					case SBreak:
						while (true){
							switch(current_frame.control){
								case CSWhile(condition), CSDoWhile(condition):
									if (frame_stack.length > 0){
										popFrame();
										break;
									}
									else{
										script_complete = true;
										_on_complete(returnValue);
										return;
									}
								case CSFor(name, iter):
									if (frame_stack.length > 0){
										popFrame();
										break;
									}
									else{
										script_complete = true;
										_on_complete(returnValue);
										return;
									}
								default:
									popFrame();
									if (current_frame == null){
										trace("Invalid continue.");
										return;
									}
							}
						}
					case SReturn:
						var result = returnValue;
						var continuing:Bool = false;
						while (frame_stack.length != 0){
							var prev_frame:StackFrame = current_frame;
							popFrame();
							switch(prev_frame.control){
								case CSCall:
									prev_frame.parent.call_results[prev_frame.call_id] = {result:result, complete:true};
									continuing = true;
									break;
								default:
							}
						}
						if (!continuing){
							_on_complete(result);
							return;
						}
				}
			}
			
			while (current_frame.pc >= current_frame.block.length){
				switch(current_frame.control){
					case CSCall:
						current_frame.parent.call_results[current_frame.call_id].complete = true;
						current_frame.parent.call_results[current_frame.call_id].result = null; //If we just got to the end of the block without returning, the result is null
					case CSFor(name, iterator):
						if (iterator.hasNext()){
							current_frame.locals.set(name, {r:iterator.next()});
							current_frame.pc = 0;
							break;
						}
					default:
				}
				#if hs_verbose
				trace("Exiting block... ");
				#end
				if (frame_stack.length != 0){
					popFrame();
				}
				else{
					if (_on_complete != null){
						script_complete = true;
						_on_complete(returnValue);
						return;
					}
				}
			}
			
		}
		if (script_complete){
			if (_on_complete != null){
				_on_complete(returnValue);
			}
		}
	}

	override public function expr( e : Expr ) : Dynamic {
		#if hs_verbose
		trace(e);
		#end
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		var entry_frame:StackFrame = current_frame;
		var entry_pc:Int = current_frame.pc;
		switch(e){
			case ECheckType(e,_):	
				var val = expr(e);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				return val;
			case EMeta(_, _, e):	
				var val = expr(e);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				return val;
			case ESwitch(e, cases, def):
				var val : Dynamic = expr(e);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				var match = false;
				for( c in cases ) {
					for( v in c.values )
						if ( expr(v) == val ) {
							if (retry_expr(entry_pc, entry_frame)) return null; 
							match = true;
							break;
						}
					if( match ) {
						val = expr(c.expr);
						if (retry_expr(entry_pc, entry_frame)) return null; 
						break;
					}
				}
				if( !match ){
					val = def == null ? null : expr(def);
					if (retry_expr(entry_pc, entry_frame)) return null; 
				}
				return val;
			case ETernary(econd, e1, e2):
				var cond = expr(econd);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				return if( cond == true ) expr(e1) else expr(e2);
			case EObject(fl):
				var o = {};
				for( f in fl )
					set(o, f.name, expr(f.e));
					if (retry_expr(entry_pc, entry_frame)) return null; 
				return o;
			case EThrow(e):
				var arg = expr(e);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				throw arg;
			case ENew(cl,params):
				var a = new Array();
				for( e in params )
					a.push(expr(e));
					if (retry_expr(entry_pc, entry_frame)) return null; 
				return cnew(cl,a);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				var index:Dynamic = expr(index);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				if (isMap(arr)) {
					return getMapValue(arr, index);
				}
				else {
					return arr[index];
				}
			case EReturn(e):
				returnValue = e == null ? null : expr(e);
				if (retry_expr(entry_pc, entry_frame)) return null; 
				throw SReturn;
			case EIf(econd, e1, e2):
				var res = expr(econd);
				if (retry_expr(entry_pc, entry_frame)) return null;
				return if( res == true ) expr(e1) else if( e2 == null ) null else expr(e2);
			case EWhile(econd, eb):
				var body:Array<Expr>;
				switch(Tools.expr(eb)){
					case EBlock(a):
						body = a;
					default:
						body = [eb];
				}
				pushFrame(new StackFrame(body, CSWhile(econd)));
				return null;
			case EDoWhile(econd, eb):
				var body:Array<Expr>;
				switch(Tools.expr(eb)){
					case EBlock(a):
						body = a;
					default:
						body = [eb];
				}
				pushFrame(new StackFrame(body, CSDoWhile(econd)));
				return null;
			case EFor(v, it, e):
				var resolved_it:Dynamic = expr(it);
				if (retry_expr(entry_pc, entry_frame)) return null;
				var iter:Iterator<Dynamic> = makeIterator(resolved_it);
				if (iter == null || !iter.hasNext()){
					return null;
				}
				var body:Array<Expr>;
				switch(Tools.expr(e)){
					case EBlock(a):
						body = a;
					default:
						body = [e];
				}
				pushFrame(new StackFrame(body, CSFor(v, iter)));
			case EBinop(op, e1, e2):
				expr(e1);
				if(retry_expr(entry_pc, entry_frame)) return null;
				expr(e2);
				if(retry_expr(entry_pc, entry_frame)) return null;
				
				reset_calls();
				
				var fop = binops.get(op);
				if( fop == null ) error(EInvalidOp(op));
				return fop(e1,e2);
			case EBlock(eb):
				pushFrame(new StackFrame(eb, CSBlock));
			case ECall(e, params):
				var args = new Array();
				for ( p in params ){
					args.push(expr(p));
					if(retry_expr(entry_pc, entry_frame)) return null;
				}
				
				switch( Tools.expr(e) ) {
				case EField(e,f):
					var obj = expr(e);
					if (retry_expr(entry_pc, entry_frame)) return null;
					if( obj == null ) error(EInvalidAccess(f));
					return fcall(obj,f,args);
				default:
					var target = expr(e);
					if(retry_expr(entry_pc, entry_frame)) return null;
					return call(null,target,args);
				}
			case EFunction(params, fexpr, name, _):
				var hasOpt = false, minParams = 0;
				for( p in params )
					if( p.opt )
						hasOpt = true;
					else
						minParams++;
				var f = function(args:Array<Dynamic>){
					if (current_frame.call_results[current_frame.call_count] != null){
						if (current_frame.call_results[current_frame.call_count].complete){
							#if hs_verbose
							trace("Call " + current_frame.call_count + " already resolved (" + current_frame.call_results[current_frame.call_count].result + ")");
							#end
							current_frame.call_count++;
							return current_frame.call_results[current_frame.call_count-1].result;
						}
					}
					#if hs_verbose
					else{
						trace("Making new call sub...");
					}
					#end
					
					var block:Array<Expr> = switch(Tools.expr(fexpr)){
						case EBlock(a):
							a;
						default:
							[fexpr];
					}
					var frame:StackFrame = new StackFrame(block, CSCall);
					
					if( args.length != params.length ) {
						if ( args.length < minParams ) {
							var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
							if( name != null ) str += " for function '" + name+"'";
							throw str;
						}
						// make sure mandatory args are forced
						var args2 = [];
						var extraParams = args.length - minParams;
						var pos = 0;
						for( p in params )
							if( p.opt ) {
								if( extraParams > 0 ) {
									args2.push(args[pos++]);
									extraParams--;
								} else
									args2.push(null);
							} else
								args2.push(args[pos++]);
						args = args2;
					}

					for( i in 0...params.length ){
						frame.locals.set(params[i].name, { r : args[i] });
					}
					
					current_frame.called = true;
					frame.call_id = current_frame.call_count;
					current_frame.call_results.push({result:null, complete:false});
					frame.parent = current_frame;
					
					pushFrame(frame);
					return null;
				};
				
				f = Reflect.makeVarArgs(f);
				if (name != null){
					locals.set(name, {r: f});
					if (frame_stack.length == 0){
						variables.set(name, f);
					}
				}
				return f;
			case EVar(n, _, e):
				var val:Dynamic = null;
				if (e != null){
					val = expr(e);
					if(retry_expr(entry_pc, entry_frame)) return null;
				}
				declared.push({ n : n, old : locals.get(n) });
				locals.set(n,{ r : (e == null)?null:val });
				return null;
			case EArrayDecl(arr):
				if (arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _))) {
					var isAllString:Bool = true;
					var isAllInt:Bool = true;
					var isAllObject:Bool = true;
					var isAllEnum:Bool = true;
					var keys:Array<Dynamic> = [];
					var values:Array<Dynamic> = [];
					for (e in arr) {
						switch(Tools.expr(e)) {
							case EBinop("=>", eKey, eValue): {
								var key:Dynamic = expr(eKey);
								if (retry_expr(entry_pc, entry_frame)) return null;
								var value:Dynamic = expr(eValue);
								if (retry_expr(entry_pc, entry_frame)) return null;
								isAllString = isAllString && Std.is(key, String);
								isAllInt = isAllInt && Std.is(key, Int);
								isAllObject = isAllObject && Reflect.isObject(key);
								isAllEnum = isAllEnum && Reflect.isEnumValue(key);
								keys.push(key);
								values.push(value);
							}
							default: throw("=> expected");
						}
					}
					var map:Dynamic = {
						if (isAllInt) new haxe.ds.IntMap<Dynamic>();
						else if (isAllString) new haxe.ds.StringMap<Dynamic>();
						else if (isAllEnum) new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
						else if (isAllObject) new haxe.ds.ObjectMap<Dynamic, Dynamic>();
						else throw 'Inconsistent key types';
					}
					for (n in 0...keys.length) {
						setMapValue(map, keys[n], values[n]);
					}
					return map;
				}
				else {
					var a = new Array();
					for ( e in arr ) {
						a.push(expr(e));
						if (retry_expr(entry_pc, entry_frame)) return null;
					}
					return a;
				}
			default:
				return super.expr(#if hscriptPos curExpr #else e #end);
		}
		return null;
	}
	
	override function restore(old:Int):Void{
		//do nothing;
	}
	
	//Query: Does this have a bug condition where it won't accept locals declared to null?
	override function resolve( id : String ) : Dynamic {
		var i:Int = frame_stack.length;
		var search_area:Map<String, Dynamic> = current_frame.locals;
		var l:Dynamic = null;
		while (i >= 0){
			i--;
			l = search_area.get(id);
			if (l != null){
				return l.r;
			}
			if(i>=0){
				search_area = frame_stack[i].locals;
			}
		}
		//if ( l != null )
		//	return l.r;
		var v = variables.get(id);
		if( v == null && !variables.exists(id) )
			error(EUnknownVariable(id));
		return v;
	}
	
	override function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch(e) {
		case EIdent(id):
			var l = find_local(id);
			
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
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				var v = getMapValue(arr, index);
				if (prefix) {
					v += delta;
					setMapValue(arr, index, v);
				}
				else {
					setMapValue(arr, index, v + delta);
				}
				return v;
			}
			else {
				var v = arr[index];
				if( prefix ) {
					v += delta;
					arr[index] = v;
				} else
					arr[index] = v + delta;
				return v;
			}
		default:
			return error(EInvalidOp((delta > 0)?"++":"--"));
		}
	}
	
	override public function assign(e1:Expr, e2:Expr):Dynamic{
		var v = expr(e2);
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			var l:Dynamic = find_local(id);
			if( l == null ){
				variables.set(id, v);
			}
			else{
				l.r = v;
			}
		case EField(e,f):
			v = set(expr(e),f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				setMapValue(arr, index, v);
			}
			else {
				arr[index] = v;
			}

		default:
			error(EInvalidOp("="));
		}
		return v;
	}
	
	/**
	   Searches from the local scope outwards until it finds the variable or returns null
	   @param	id	The name of the variable
	   @return		The resolved variable, or null
	**/
	private inline function find_local(id:String):Dynamic{
		var i:Int = frame_stack.length;
		var search_area:Map<String, Dynamic> = current_frame.locals;
		var l:Dynamic = null;
		while (i >= 0){
			i--;
			l = search_area.get(id);
			if (l != null){
				break;
			}
			if(i>=0){
				search_area = frame_stack[i].locals;
			}
		}
		return l;
	}

	/**
	   If we've changed frame in the middle of a non-sliceable expression, this inline detects that, 
	   and rolls back the PC on the previous frame so as to retry that expression's evaluation once the 
	   new frame (likely spawned by a user-space function call) has returned a value.
	**/
	private inline function retry_expr(old_pc:Int, old_frame:StackFrame):Bool{
		if (current_frame != old_frame){
			old_frame.pc = old_pc;
			old_frame.call_count = 0;
			return true;
		}
		
		return false;
	}
	
	private inline function reset_calls():Void{
		current_frame.call_count = 0;
	}
}


enum ControlStructure{
	CSBlock;
	CSFor(name:String, iterator:Iterator<Dynamic>);
	CSWhile(condition:Expr);
	CSDoWhile(condition:Expr);
	CSCall;
}

class StackFrame 
{
	private static var next_id:Int = 0;
	public var id:Int;
	public var pc:Int;
	public var block:Array<Expr>;
	public var control:ControlStructure;
	public var locals:Map<String, {r: Dynamic}>;
	public var call_results:Array<{result:Dynamic, complete:Bool}>;
	public var call_count:Int = 0;
	public var call_id:Int = -1;
	public var called:Bool = false;
	public var parent:StackFrame;
	
	public function new(block:Array<Expr>, control:ControlStructure) 
	{
		this.id = next_id;
		next_id++;
		this.pc = 0;
		this.locals = new Map();
		this.call_results = [];
		this.block = block;
		this.control = control;
		
		//Loop structures are modified to just have an if-statement that resets the frame's program counter if necessary
		switch(control){
			case CSWhile(condition):
				this.block = block.concat([]);
				#if hscriptPos
				this.block.push(Tools.mk(EIf(condition, Tools.mk(ECall(Tools.mk(EIdent('__intern_reset_pc'), condition), []), condition)), condition));
				#else
				this.block.push(EIf(condition, ECall(EIdent('__intern_reset_pc'), [])));
				#end
				pc = this.block.length-1;
			case CSDoWhile(condition):
				this.block = block.concat([]);
				#if hscriptPos
				this.block.push(Tools.mk(EIf(condition, Tools.mk(ECall(Tools.mk(EIdent('__intern_reset_pc'), condition), []), condition)), condition));
				#else
				this.block.push(EIf(condition, ECall(EIdent('__intern_reset_pc'), [])));
				#end
			case CSFor(name, iterator):
				//we can guarantee the iterator is valid and hasNext here, because expr(e) won't spawn one of these otherwise :>
				locals.set(name, {r:iterator.next()});
			default:
		}
	}
	

}
