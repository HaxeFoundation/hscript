import haxe.ds.EnumValueMap;
import haxe.ds.Option;
import hscript.Macro;
import hscript.Tools;
import hscript.Async;
import hscript.Printer;
import hscript.Checker;
import haxe.unit.*;

class TestHScript extends TestCase {

	var optimize : Bool;

	function new(optimize=false) {
		this.optimize = optimize;
		super();
	}

	function assertScript(x,v:Dynamic,?vars : Dynamic, allowTypes=false, ?pos:haxe.PosInfos) {
		var p = new hscript.Parser();
		p.allowTypes = allowTypes;
		var program = p.parseString(x);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		var interp = new hscript.Interp();
		#if js
		if( optimize ) interp = new hscript.JsInterp();
		#end
		if( vars != null )
			for( v in Reflect.fields(vars) )
				interp.variables.set(v,Reflect.field(vars,v));
		var ret : Dynamic = interp.execute(program);
		assertEquals(v, ret, pos);
	}

	function test():Void {
		assertScript("0",0);
		assertScript("0xFF", 255);
		#if !(php || python)
			#if haxe3
			assertScript("0xBFFFFFFF", 0xBFFFFFFF);
			assertScript("0x7FFFFFFF", 0x7FFFFFFF);
			#elseif !neko
			assertScript("n(0xBFFFFFFF)", 0xBFFFFFFF, { n : haxe.Int32.toNativeInt });
			assertScript("n(0x7FFFFFFF)", 0x7FFFFFFF, { n : haxe.Int32.toNativeInt } );
			#end
		#end
		assertScript("-123",-123);
		assertScript("- 123",-123);
		assertScript("1.546",1.546);
		assertScript(".545",.545);
		assertScript("1e5",100000);
		assertScript("1.2e2",120);
		assertScript("100e-2",1);
		assertScript("1.2e-1",0.12);
		assertScript("'bla'","bla");
		assertScript("null",null);
		assertScript("true",true);
		assertScript("false",false);
		assertScript("1 == 2",false);
		assertScript("1.3 == 1.3",true);
		assertScript("5 > 3",true);
		assertScript("0 < 0",false);
		assertScript("-1 <= -1",true);
		assertScript("1 + 2",3);
		assertScript("~545",-546);
		assertScript("'abc' + 55","abc55");
		assertScript("'abc' + 'de'","abcde");
		assertScript("-1 + 2",1);
		assertScript("1 / 5",0.2);
		assertScript("3 * 2 + 5",11);
		assertScript("3 * (2 + 5)",21);
		assertScript("3 * 2 // + 5 \n + 6",12);
		assertScript("3 /* 2\n */ + 5",8);
		assertScript("[55,66,77][1]",66);
		assertScript("[11,22,33,][2]", 33);
		assertScript("var a = [55]; a[0] *= 2; a[0]",110);
		assertScript("x",55,{ x : 55 });
		assertScript("var y = 33; y",33);
		assertScript("{ 1; 2; 3; }",3);
		assertScript("{ var x = 0; } x",55,{ x : 55 });
		assertScript("o.val",55,{ o : { val : 55 } });
		assertScript("o.val",null,{ o : {} });
		assertScript("var a = 1; a++",1);
		assertScript("var a = 1; a++; a",2);
		assertScript("var a = 1; ++a",2);
		assertScript("var a = 1; a *= 3",3);
		assertScript("a = b = 3; a + b",6);
		assertScript("add(1,2)",3,{ add : function(x,y) return x + y });
		assertScript("a.push(5); a.pop() + a.pop()",8,{ a : [3] });
		assertScript("if( true ) 1 else 2",1);
		assertScript("if( false ) 1 else 2",2);
		assertScript("var t = 0; for( x in [1,2,3] ) t += x; t",6);
		assertScript("var a = new Array(); for( x in 0...5 ) a[x] = x; a.join('-')","0-1-2-3-4");
		assertScript("(function(a,b) return a + b)(4,5)",9);
		assertScript("var y = 0; var add = function(a) y += a; add(5); add(3); y", 8);
		assertScript("var a = [1,[2,[3,[4,null]]]]; var t = 0; while( a != null ) { t += a[0]; a = a[1]; }; t",10);
		assertScript("var a = false; do { a = true; } while (!a); a;",true);
		assertScript("var t = 0; for( x in 1...10 ) t += x; t", 45);
		assertScript("var t = 0; for( x in new IntIterator(1,10) ) t +=x; t", 45);
		assertScript("var x = 1; try { var x = 66; throw 789; } catch( e : Dynamic ) e + x",790);
		assertScript("var x = 1; var f = function(x) throw x; try f(55) catch( e : Dynamic ) e + x",56);
		assertScript("var i=2; if( true ) --i; i",1);
		assertScript("var i=0; if( i++ > 0 ) i=3; i",1);
		assertScript("var a = 5/2; a",2.5);
		assertScript("{ x = 3; x; }", 3);
		assertScript("{ x : 3, y : {} }.x", 3);
		assertScript("function bug() return { \n }\nbug().x", null);
		assertScript("1 + 2 == 3", true);
		assertScript("-2 == 3 - 5", true);
		assertScript("var x=-3; x", -3);
		assertScript("var a:Array<Dynamic>=[1,2,4]; a[2]", 4, null, true);
		assertScript("/**/0", 0);
		assertScript("x=1;x*=-2", -2);
		assertScript("var f = x -> x + 1; f(3)", 4);
		assertScript("var f = () -> 55; f()", 55);
		assertScript("var f = (x) -> x + 1; f(3)", 4);
		assertScript("var f = (x:Int) -> x + 1; f(3)", 4);
		assertScript("var f = (x,y) -> x + y; f(3,1)", 4);
		assertScript("var f = (x,y:Int) -> x + y; f(3,1)", 4);
		assertScript("var f = (x:Int,y:Int) -> x + y; f(3,1)", 4);
		assertScript("var f:Int->Int->Int = (x:Int,y:Int) -> x + y; f(3,1)", 4, null, true);
		assertScript("var f:(x:Int, y:Int)->Int = (x:Int,y:Int) -> x + y; f(3,1)", 4, null, true);
		assertScript("var f:(x:Int)->(y:Int, z:Int)->Int = (x:Int) -> (y:Int, z:Int) -> x + y + z; f(3)(1, 2)", 6, null, true);
		assertScript("var f:(x:Int)->(Int, Int)->Int = (x:Int) -> (y:Int, z:Int) -> x + y + z; f(3)(1, 2)", 6, null, true);
		assertScript("var a = 10; var b = 5; a - -b", 15);
		assertScript("var a = 10; var b = 5; a - b / 2", 7.5);
		assertScript("var a; a", null);
		assertScript("var a = 1, b = 5; a + b;", 6);
		assertScript("var a, b = 5; if (a == null) a = 2; a + b;", 7);
		assertScript("var a:Int; a", null, null, true);
		assertScript("var a:Int = 1, b:Int = 5; a + b;", 6, null, true);
		assertScript("var a:Int, b:Int = 5; if (a == null) a = 2; a + b;", 7, null, true);
		assertScript("false && xxx", false);
		assertScript("true || xxx", true);
		assertScript("[for( x in arr ) switch( x ) { case 1: 55; case 3: 66; default: 0; }].join(':')",'55:0:66',{ arr : [1,2,3] });
		assertScript("switch( x ) { case 1: 55; case 3: 66; default: 0; }",66 ,{ x : 3 });
		assertScript("var a = 1; switch( b ) { default: a = 2; }; a", 2, { b : 2 });
		assertScript("var a = 1; switch( b ) { case 2: a = 100; default: a = 2; }; a", 100, { b : 2 });
		assertScript("var a = 3; switch( b ) { case 2: if (a == 1) { a = 100; } else { a = 99; }; default: a = 2; }; a", 99, { b : 2 });
	}

	function testNullFieldAccess():Void {
		var pt = {
			x : 10,
			call : function() { return 11; }
		};
		var vars = {
			ptnull : null,
			pt: pt,
			pt2null : {pt : null},
			pt2: {pt : pt}
		}
		assertScript("ptnull?.x", null, vars);
		assertScript("ptnull?.pt.x", null, vars);
		assertScript("ptnull?.call()", null, vars);
		assertScript("pt?.x", 10, vars);
		assertScript("pt?.call()", 11, vars);
		assertScript("pt2null?.pt", null, vars);
		assertScript("pt2null?.pt?.x", null, vars);
		assertScript("pt2null?.pt?.call()", null, vars);
		assertScript("pt2?.pt", pt, vars);
		assertScript("pt2?.pt?.x", 10, vars);
		assertScript("pt2?.pt?.call()", 11, vars);
	}

	function testIsOperator():Void {
		var vars = {
			String: String,
			Bool: Bool,
			Int: Int,
			Float: Float,
			Dynamic: Dynamic
		}
		assertScript("10 is Int", true, vars);
		assertScript("10.0 is Int", true, vars);
		assertScript("10.1 is Int", false, vars);
		assertScript("10 is Float", true, vars);
		assertScript("10.0 is Float", true, vars);
		assertScript("10.1 is Float", true, vars);
		assertScript("10 is String", false, vars);
		assertScript('"hscript" is String', true, vars);
		assertScript('"" is String', true, vars);
		assertScript('true is Bool', true, vars);
		assertScript('false is Bool', true, vars);
		assertScript('0 is Bool', false, vars);
		assertScript('1 is Bool', false, vars);
		assertScript('1 is Bool', false, vars);
		assertScript("10 is Dynamic", true, vars);
		assertScript("10.1 is Dynamic", true, vars);
		assertScript('"hscript" is Dynamic', true, vars);
		assertScript('null is Int', false, vars);
		assertScript('null is Float', false, vars);
		assertScript('null is String', false, vars);
		assertScript('null is Bool', false, vars);
		assertScript('null is Dynamic', false, vars);
	}

	function testMap():Void {
		var objKey = { ok:true };
		var vars = {
			stringMap: ["foo" => "Foo", "bar" => "Bar"],
			intMap:[100 => "one hundred"],
			objKey: objKey,
			objMap:[objKey => "ok"],
			enumKey:Option.Some("some"),
			enumMap:new EnumValueMap<Option<String>, String>(),
			stringIntMap: ["foo" => 100]
		}
		vars.enumMap.set(vars.enumKey, "ok");

		assertScript('stringMap["foo"]', "Foo", vars);
		assertScript('intMap[100]', "one hundred", vars);
		assertScript('objMap[objKey]', "ok", vars);
		assertScript('enumMap[enumKey]', "ok", vars);
		assertScript('stringMap["a"] = "A"; stringMap["a"]', "A", vars);
		assertScript('intMap[200] = objMap[{foo:false}] = enumMap[enumKey] = "A"', "A", vars);
		assertEquals('A', vars.intMap[200]);
		assertEquals('A', vars.enumMap.get(vars.enumKey));
		for (key in vars.objMap.keys()) {
			if (key != objKey) {
				assertEquals(false, (key:Dynamic).foo);
				assertEquals('A', vars.objMap[key]);
			}
		}

		assertScript('
			var keys = [];
			for (key in stringMap.keys()) keys.push(key);
			keys.join("_");
		', {
			var keys = [];
			for (key in vars.stringMap.keys()) keys.push(key);
			keys.join("_");
		}, vars);
		assertScript('stringMap.remove("foo"); stringMap.exists("foo");', false, vars);
		assertScript('stringMap["foo"] = "a"; stringMap["foo"] += "b"', 'ab', vars);
		assertEquals('ab', vars.stringMap['foo']);
		assertScript('stringIntMap["foo"]++', 100, vars);
		assertEquals(101, vars.stringIntMap['foo']);
		assertScript('++stringIntMap["foo"]', 102, vars);
		assertScript('var newMap = ["foo"=>"foo"]; newMap["foo"];', 'foo', vars);
		#if (!php || (haxe_ver >= 3.3))
		assertScript('var newMap = [enumKey=>"foo"]; newMap[enumKey];', 'foo', vars);
		#end
		assertScript('var newMap = [{a:"a"}=>"foo", objKey=>"bar"]; newMap[objKey];', 'bar', vars);
	}

	static function main() {
		#if ((haxe_ver < 4) && php)
		// uncaught exception: The each() function is deprecated. This message will be suppressed on further calls (errno: 8192)
		// in file: /Users/travis/build/andyli/hscript/bin/lib/Type.class.php line 178
		untyped __php__("error_reporting(E_ALL ^ E_DEPRECATED);");
		#end

		var runner = new TestRunner();
		runner.add(new TestHScript());
		runner.add(new TestHScript(true));
		var succeed = runner.run();

		#if sys
			Sys.exit(succeed ? 0 : 1);
		#elseif flash
			flash.system.System.exit(succeed ? 0 : 1);
		#else
			if (!succeed)
				throw "failed";
		#end
	}

}
