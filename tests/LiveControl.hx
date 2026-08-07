package tests;

class LiveControl extends LiveTest {

	public function new() {
		checkBranches();
		checkLoops();
		checkExceptions();
		checkSwitch();
	}

	function raise() {
		throw "err";
	}

	function fib( n : Int ) : Int {
		if( n <= 1 )
			return n;
		return fib(n-1) + fib(n-2);
	}

	function sign( v : Int ) {
		if( v > 0 )
			return 1;
		else if( v < 0 )
			return -1;
		return 0;
	}

	function checkBranches() {
		var v = 3;
		var r = "";
		if( v > 2 ) r = "gt" else r = "le";
		eq(r, "gt");
		if( v > 10 ) fail("unreachable");
		eq(sign(5), 1);
		eq(sign(-5), -1);
		eq(sign(0), 0);
	}

	function checkLoops() {
		var i = 0, sum = 0;
		while( i < 5 ) {
			sum += i;
			i++;
		}
		eq(sum, 10);

		var j = 0;
		do {
			j++;
		} while( j < 3 );
		eq(j, 3);

		var t = 0;
		for( k in 0...10 ) {
			if( k == 3 ) continue;
			if( k == 7 ) break;
			t += k;
		}
		eq(t, 18);

		var acc = [];
		for( s in ["a","b","c"] )
			acc.push(s.toUpperCase());
		eq(acc.join(""), "ABC");

		var grid = [];
		for( y in 0...3 )
			for( x in 0...3 )
				if( x == y ) grid.push(x);
		eq(grid.join("-"), "0-1-2");

		eq(fib(10), 55);
	}

	function checkExceptions() {
		var caught = null;
		try raise() catch( e : String ) caught = e;
		eq(caught, "err");
		try {
			throw "custom";
		} catch( e : String ) {
			eq(e, "custom");
		}
		caught = null;
		try {
			indirect();
		} catch( e : String ) {
			caught = e;
		}
		eq(caught, "err");
	}

	function indirect() {
		raise();
	}

	function checkSwitch() {
		var out = [];
		for( k in 0...4 )
			out.push(switch( k ) {
			case 0: "zero";
			case 1, 2: "small";
			default: "big";
			});
		eq(out.join(","), "zero,small,small,big");
		var s = "b";
		switch( s ) {
		case "a": fail("unreachable");
		case "b": eq(s, "b");
		default: fail("unreachable");
		}
	}

}
