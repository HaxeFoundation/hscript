package tests;

class LiveBasic extends LiveTest {

	var counter : Int;
	var name : String;

	public function new() {
		counter = 0;
		name = "basic";
		checkOps();
		checkCalls();
		eq(counter, 3);
	}

	function add( a : Int, b : Int ) {
		counter++;
		return a + b;
	}

	function mul( a : Int, b : Int ) : Int {
		return a * b;
	}

	function greet( who : String ) {
		return "hello " + (who == null ? "world" : who);
	}

	function checkOps() {
		var x = 10;
		x += 5;
		x *= 2;
		x -= 1;
		eq(x, 29);
		eq(x % 4, 1);
		eq(x >> 1, 14);
		eq(x << 1, 58);
		eq(x & 7, 5);
		eq(x | 2, 31);
		eq(x ^ 1, 28);
		eq(~x, -30);
		eq(-x, -29);
		eq(x / 2, 14.5);
		eq(x++, 29);
		eq(x, 30);
		eq(--x, 29);
		assert(x > 20);
		assert(!(x < 20));
		assert(x == 29 && x != 30);
		assert(x < 0 || x > 0);
		eq(x > 20 ? "big" : "small", "big");
		var s = "abc";
		eq(s + 55, "abc55");
		eq(s + s, "abcabc");
		eq(s == "abc", true);
		eq(s.length, 3);
		eq(s.charAt(1), "b");
		var n = null;
		eq(n ?? "def", "def");
		eq(s ?? "def", "abc");
	}

	function checkCalls() {
		eq(add(1,2), 3);
		eq(mul(add(2,3), 4), 20);
		eq(counter, 2);
		eq(add(mul(2,3), mul(2,2)), 10);
		eq(greet(null), "hello world");
		eq(greet("live"), "hello live");
		eq(name, "basic");
		name = "changed";
		eq(name, "changed");
		name = "basic";
		eq(label(55), "[55]");
		eq(this.label("x"), "[x]");
	}

}
