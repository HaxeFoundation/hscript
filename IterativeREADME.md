IterativeInterp
===============

An alternative interpreter that has been frankensteined into running somewhat iteratively. 

Usage
-----

Make a new instance of IterativeInterp:
`var myInterp = new IterativeInterp();`

Pass `prepareScript` a script (`Expr`) that has been parsed with the regular `hscript.Parser` parser, as well as an optional `Dynamic->Void` callback function.

`myInterp.prepareScript(myScript, myCallbackFunction)`

Step through the script however you wish. An OpenFL example would be:
```
//Each frame, run the interpreter for 100 steps or until the script returns (whichever comes first) 
addEventListener(Event.ENTER_FRAME, function(e){
	myInterp.step(100);
});
```

Mechanism
---------
There are two major changes from the original, fully-recursive interpreter.

First, the contents of Expr.EBlock(a:Array<Expr>) expressions are now evaluated one-Expr-per-step, rather than all in one call. This ensures that `while` and other loops cannot lock up your program; even if the script is in an infinite loop, it will yield after the step amount given in `IterativeInterp.step(steps:Int)`. Each nested EBlock runs in its own Haxe-level stack frame, with local variable access attempts bubbling up to higher stack frames. 
	
Second, functions defined within a script now indicate that they have been called via `ECall`, and all `Expr`s that could return a value will first check whether that `Expr` is an `ECall` waiting on a result before returning. A hscript-defined function being evaluated will force the script to re-attempt the current `Expr` evaluation before continuing.

Use Case
--------
IterativeInterp is intended to be used in situations where arbitrary hscript is being executed on non-threaded targets, to ensure that said hscript cannot crash or infinitely hang the program. 

Drawbacks
---------
As all value-returning expressions are now essentially checking for function calls, and multiple function calls (such as an array declared with multiple members all being the result of a function call), there is considerable overhead. IterativeInterp is likely to be several factors slower than regular Interp.
