package tests;

class LiveStd extends LiveTest {

	public function new() {
		checkStd();
		checkString();
		checkArray();
		checkClosures();
	}

	function makePoint( x : Int, y : Int ) {
		return { x : x, y : y };
	}

	function checkStd() {
		eq(Std.int(7 / 2), 3);
		eq(Std.parseInt("42"), 42);
		eq(Std.string(true), "true");
		eq(Std.string(12), "12");
	}

	function checkString() {
		var s = "Hello,World";
		eq(s.toLowerCase(), "hello,world");
		eq(s.toUpperCase(), "HELLO,WORLD");
		eq(s.substr(0,5), "Hello");
		eq(s.substring(6,11), "World");
		eq(s.indexOf("World"), 6);
		eq(s.lastIndexOf("l"), 9);
		eq(s.charAt(0), "H");
		eq(s.charCodeAt(0), 72);
		eq(s.split(",").join("+"), "Hello+World");
		eq(StringTools.startsWith(s,"Hello"), true);
		eq(StringTools.endsWith(s,"World"), true);
		eq(StringTools.replace(s,",", " "), "Hello World");
		eq(StringTools.lpad("7","0",3), "007");
		var sb = new StringBuf();
		sb.add("a");
		sb.add(1);
		eq(sb.toString(), "a1");
	}

	function checkArray() {
		var a = [5,3,8,1];
		eq(a.length, 4);
		a.sort(function(x,y) return x - y);
		eq(a.join(","), "1,3,5,8");
		eq(a.indexOf(8), 3);
		eq(a.slice(1,3).join(","), "3,5");
		eq(a.pop(), 8);
		eq(a.shift(), 1);
		eq(a.join(","), "3,5");
		a.unshift(7);
		eq(a.join(","), "7,3,5");
		eq(a.concat([4]).join(","), "7,3,5,4");
		eq([for( v in a ) v * 2].join(","), "14,6,10");
		eq(a.map(function(v) return v + 1).join(","), "8,4,6");
		eq(a.filter(function(v) return v > 4).join(","), "7,5");
		var it = 0;
		for( v in a ) it += v;
		eq(it, 15);
		eq(new Array().length, 0);
	}

	function checkClosures() {
		var f = function(v) return v * 2;
		eq(f(21), 42);
		var count = 0;
		var inc = function() count++;
		inc();
		inc();
		eq(count, 2);
		var p = makePoint(3,4);
		eq(p.x + "," + p.y, "3,4");
		var apply = function(fn:Int->Int,v:Int) return fn(v);
		eq(apply(f, 5), 10);
	}

}
