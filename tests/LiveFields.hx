package tests;

class LiveFields extends LiveTest {

	var ints : Array<Int> = [1,2,3];
	var text : String = "init";
	var flag : Bool;
	var unset : String;
	public var total : Int = 0;

	public function new() {
		eq(text, "init");
		eq(ints.join(","), "1,2,3");
		eq(total, 0);
		flag = true;
		total = ints.length;
		text += "-ctor";
		checkFields();
		checkStructures();
		eq(text, "init-ctor");
	}

	function checkFields() {
		eq(flag, true);
		eq(total, 3);
		ints.push(4);
		eq(ints.length, 4);
		eq(ints[2], 3);
		ints[0] = 10;
		eq(ints[0], 10);
		ints[1] += 5;
		eq(ints[1], 7);
		ints[3]++;
		eq(ints.join(","), "10,7,3,5");
		total += 5;
		total++;
		eq(total, 9);
		eq(this.flag, true);
		eq(this.ints[0], 10);
		this.ints[0] += 1;
		eq(this.ints[0], 11);
		this.ints[0] = 10;
		this.text += "!";
		eq(this.text, "init-ctor!");
		this.text = "init-ctor";
		eq(unset, null);
		eq(unset == null ? "null" : unset, "null");
		eq(unset ?? "default", "default");
		unset = "set";
		eq(unset ?? "default", "set");
	}

	function checkStructures() {
		var o = { x : 1, y : "two" };
		eq(o.x + ":" + o.y, "1:two");
		o.x++;
		eq(o.x, 2);
		o.y = "three";
		eq(o.y, "three");
		var nested = { pt : { x : 5 }, list : [1,2] };
		eq(nested.pt.x, 5);
		eq(nested.list.length, 2);

		var m = new haxe.ds.StringMap();
		m.set("a", 1);
		m.set("b", 2);
		eq(m.get("a") + m.get("b"), 3);
		eq(m.exists("c"), false);
		m.set("c", 3);
		eq(m.get("c"), 3);
		m.remove("a");
		eq(m.exists("a"), false);
	}

}
