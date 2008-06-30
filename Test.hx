class Test {

	static function main() {
		var script = "
			var sum = 0;
			for( a in angles )
				sum = sum + Math.cos(a);
			sum;
		";
		var p = new hscript.Parser();
		var program = p.parseString(script);
		var interp = new hscript.Interp();
		interp.variables.set("Math",Math); // share the Math class
		interp.variables.set("angles",[0,1,2,3]); // set the angles list
		trace( interp.execute(program) );
	}

}