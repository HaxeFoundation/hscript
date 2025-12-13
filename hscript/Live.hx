package hscript;

/**
	If your class implements hscript.Live, it will support realtime class edition. Everytime you change
	the code of a function or add a variable, the class will get retyped with hscript.Checker and modified
	functions will be patched so they are run using hscript.Interp mode. This is slower than native compilation
	but allows for faster iteration.
**/
@:autoBuild(hscript.LiveClass.build())
extern interface Live {
}
