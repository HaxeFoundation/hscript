IterativeInterp
===============

An alternative interpreter that has been frankensteined into running somewhat iteratively. 

Usage:

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
