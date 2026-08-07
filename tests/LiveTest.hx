package tests;

@:autoBuild(hscript.LiveClass.build())
class LiveTest {

	public function assert( b : Bool ) {
		if( b != true ) fail("assert failed");
	}

	public function eq( value : Dynamic, expected : Dynamic ) {
		if( value != expected ) fail(Std.string(value)+" should be "+Std.string(expected));
	}

	public function fail( msg : String ) {
		throw Type.getClassName(Type.getClass(this))+" : "+msg;
	}

	function label( v : Dynamic ) {
		return "["+Std.string(v)+"]";
	}

}
