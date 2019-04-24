hscript
=======

[![TravisCI Build Status](https://travis-ci.org/HaxeFoundation/hscript.svg?branch=master)](https://travis-ci.org/HaxeFoundation/hscript)
[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/github/HaxeFoundation/hscript?branch=master&svg=true)](https://ci.appveyor.com/project/HaxeFoundation/hscript)

Parse and evalutate Haxe expressions.


In some projects it's sometimes useful to be able to interpret some code dynamically, without recompilation.

Haxe script is a complete subset of the Haxe language.

It is dynamically typed but allows all Haxe expressions apart from type (class,enum,typedef) declarations.

Usage
-----

```haxe
var expr = "var x = 4; 1 + 2 * x";
var parser = new hscript.Parser();
var ast = parser.parseString(expr);
var interp = new hscript.Interp();
trace(interp.execute(ast));
```

In case of a parsing error an `hscript.Expr.Error` is thrown. You can use `parser.line` to check the line number.

You can set some globaly accessible identifiers by using `interp.variables.set("name",value)`

Example
-------

Here's a small example of Haxe Script usage :
```haxe
var script = "
	var sum = 0;
	for( a in angles )
		sum += Math.cos(a);
	sum; 
";
var parser = new hscript.Parser();
var program = parser.parseString(script);
var interp = new hscript.Interp();
interp.variables.set("Math",Math); // share the Math class
interp.variables.set("angles",[0,1,2,3]); // set the angles list
trace( interp.execute(program) ); 
```

This will calculate the sum of the cosines of the angles given as input.

Haxe Script has not been really optimized, and it's not meant to be very fast. But it's entirely crossplatform since it's pure Haxe code (it doesn't use any platform-specific API).

Advanced Usage
--------------

When compiled with `-D hscriptPos` you will get fine error reporting at parsing time.

You can subclass `hscript.Interp` to override behaviors for `get`, `set`, `call`, `fcall` and `cnew`.

You can add more binary and unary operations to the parser by setting `opPriority`, `opRightAssoc` and `unops` content.

You can use `parser.allowJSON` to allow JSON data.

You can use `parser.allowTypes` to parse types for local vars, exceptions, function args and return types. Types are ignored by the interpreter.

You can use `parser.allowMetadata` to parse metadata before expressions on in anonymous types. Metadata are ignored by the interpreter.

You can use `new hscript.Macro(pos).convert(ast)` to convert an hscript AST to a Haxe macros one.

Limitations
-----------

Compared to Haxe, limitations are :

- no type declarations (classes, enums, typedefs) : only expressions
- `switch` construct is supported but not pattern matching (no variable capture, we use strict equality to compare `case` values and `switch` value)
- only one variable declaration is allowed in `var`
- the parser supports optional types for `var` and `function` if `allowTypes` is set, but the interpreter ignores them
- you can enable per-expression position tracking by compiling with `-D hscriptPos`

Install
-------

In order to install Haxe Script, use `haxelib install hscript` and compile your program with `-lib hscript`.

There are only three files in hscript :

  - `hscript.Expr` : contains enums declarations
  - `hscript.Parser` : a small parser that turns a string into an expression structure (AST)
  - `hscript.Interp` : a small interpreter that execute the AST and returns the latest evaluated value
