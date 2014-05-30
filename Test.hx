class Test {

	static function test(x,v:Dynamic,?vars : Dynamic) {
		var p = new hscript.Parser();
		var program = p.parseString(x);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		var interp = new hscript.Interp();
		if( vars != null )
			for( v in Reflect.fields(vars) )
				interp.variables.set(v,Reflect.field(vars,v));
		var ret : Dynamic = interp.execute(program);
		if( v != ret ) throw ret+" returned while "+v+" expected";
	}

	static function main() {
		test("0",0);
		test("0xFF", 255);
		#if haxe3
		test("0xBFFFFFFF",0xBFFFFFFF);
		test("0x7FFFFFFF", 0x7FFFFFFF);
		#elseif !neko
		test("n(0xBFFFFFFF)",0xBFFFFFFF,{ n : haxe.Int32.toNativeInt });
		test("n(0x7FFFFFFF)", 0x7FFFFFFF, { n : haxe.Int32.toNativeInt } );
		#end
		test("-123",-123);
		test("- 123",-123);
		test("1.546",1.546);
		test(".545",.545);
		test("'bla'","bla");
		test("null",null);
		test("true",true);
		test("false",false);
		test("1 == 2",false);
		test("1.3 == 1.3",true);
		test("5 > 3",true);
		test("0 < 0",false);
		test("-1 <= -1",true);
		test("1 + 2",3);
		test("~545",-546);
		test("'abc' + 55","abc55");
		test("'abc' + 'de'","abcde");
		test("-1 + 2",1);
		test("1 / 5",0.2);
		test("3 * 2 + 5",11);
		test("3 * (2 + 5)",21);
		test("3 * 2 // + 5 \n + 6",12);
		test("3 /* 2\n */ + 5",8);
		test("[55,66,77][1]",66);
		test("var a = [55]; a[0] *= 2; a[0]",110);
		test("x",55,{ x : 55 });
		test("var y = 33; y",33);
		test("{ 1; 2; 3; }",3);
		test("{ var x = 0; } x",55,{ x : 55 });
		test("o.val",55,{ o : { val : 55 } });
		test("o.val",null,{ o : {} });
		test("var a = 1; a++",1);
		test("var a = 1; a++; a",2);
		test("var a = 1; ++a",2);
		test("var a = 1; a *= 3",3);
		test("a = b = 3; a + b",6);
		test("add(1,2)",3,{ add : function(x,y) return x + y });
		test("a.push(5); a.pop() + a.pop()",8,{ a : [3] });
		test("if( true ) 1 else 2",1);
		test("if( false ) 1 else 2",2);
		test("var t = 0; for( x in [1,2,3] ) t += x; t",6);
		test("var a = new Array(); for( x in 0...5 ) a[x] = x; a.join('-')","0-1-2-3-4");
		test("(function(a,b) return a + b)(4,5)",9);
		test("var y = 0; var add = function(a) y += a; add(5); add(3); y", 8);
		test("var a = [1,[2,[3,[4,null]]]]; var t = 0; while( a != null ) { t += a[0]; a = a[1]; }; t",10);
		test("var t = 0; for( x in 1...10 ) t += x; t", 45);
		#if haxe3
		test("var t = 0; for( x in new IntIterator(1,10) ) t +=x; t", 45);
		#else
		test("var t = 0; for( x in new IntIter(1,10) ) t +=x; t", 45);
		#end
		test("var x = 1; try { var x = 66; throw 789; } catch( e : Dynamic ) e + x",790);
		test("var x = 1; var f = function(x) throw x; try f(55) catch( e : Dynamic ) e + x",56);
		test("var i=2; if( true ) --i; i",1);
		test("var i=0; if( i++ > 0 ) i=3; i",1);
		test("var a = 5/2; a",2.5);
		test("{ x = 3; x; }", 3);
		test("{ x : 3, y : {} }.x", 3);
		test("function bug(){ \n }\nbug().x", null);
		test("1 + 2 == 3", true);
		test("-2 == 3 - 5", true);
		test("(true ? 6 : 999) - (false ? 333 : 1)",5);

		// Expect an interpreter error message with the name of the misspelled function
		test("var msg=''; var obj = {}; obj.sum = function(a,b) return a + b; try { obj.sum_misspelled(1, 2); } catch (e:Dynamic) { msg = e+''; }; msg.indexOf('sum_misspelled')>=0",true);

		#if hscriptPos
			// If compiled with hscriptPos, expect a formatted parser error message:
			//	Error: Parse error: EUnexpected()),	 on line 2, char 21-21
			//	> 1: var a=1; var b=2;
			//	> 2: trace('a+b='+(a + b)));
			//														^
			//	> 3: trace('complete!');
			//	> 4: 

			try {
				test("var a=1; var b=2;\ntrace('a+b='+(a + b)));\ntrace('complete!');\n",true);
			} catch (e:Dynamic) {
				if ((e+'').indexOf("on line 2, char 21")<0) {
					trace(e);
					throw "Expected nicely formatted parse error message";
				}
			}
		#end

		trace("Done");
	}

}