local form = require("luali.form")
local parse = require("luali.parse")
local util = require("luali.util")

local cons = form.cons

local function eval(s)
  print("--")
  print("eval:", s)
  local env = form.env()
  parse.parse(
    coroutine.wrap(function() coroutine.yield(s) end),
    function(lisp_form)
      local code = form.compile(lisp_form, env)
      print("lua:", code)
      local f, error = loadstring("return " .. code)
      if error then
        print("load error:", error)
      else
        local result = {pcall(f)}
        print(result[1] and "return:" or "error:", select(2, unpack(result)))
      end
      print()
  end)
end

local function eval_lisp(s)
  print("--")
  print("eval lisp:", s)
  local env = form.env()
  parse.parse(
    coroutine.wrap(function() coroutine.yield(s) end),
    function(lisp_form)
      local result = {pcall(function() return form.eval(lisp_form, env) end)}
      print(result[1] and "return:" or "error:")
      util.dump(select(2, unpack(result)))
    end
  );
end

eval("  hoge piyo foo")
eval("hoge   ")
eval("true")
eval("false")
eval("nil")
eval("-23.4e5")
eval('"foo"')
eval('"fo\\\"oo"')
eval("'bar")
eval("''bar")
eval("'nil")
eval("(foo)")
eval("(print a 123 nil true -123)")
eval("()")
eval(" ( ) ")
eval("(list 'foo (f 1 2 3) (b nil false true \"hoge\"))")
eval('{"x" 12 "y" 34}')
eval('["a" "b" "c"]')
eval("((fn (x y) (print (+ x y))))")
eval("((fn ()))")
eval("((fn (x) (print x) (+ x 1)))")
eval("((fn () 123))")
eval("(if (== (+ 1 1) 2) \"two!\" \"other!\")")
eval("(if (== 1 2) (print \"foo\"))")
eval("((fn))")
eval("((fn (x y) (+ 100 (+ x y))) 12 34)")
eval("(if (== (+ 1 1) 2) \"two!\" \"other!\")")

eval_lisp("true")
eval_lisp("print")
eval_lisp("(print 123.456 true nil false)")
eval_lisp("(math.pow (+ 8 4) 3)")
eval_lisp("((. \"pow\" math) 12 3)")
eval_lisp("(if (== (+ 1 1) 2) \"two!\" \"other!\")")
eval_lisp("(if (== (+ 1 2) 2) \"two!\" \"other!\")")
eval_lisp("(print x) ((fn (x y) (+ 100 (+ x y))) 12 34) (print x)")
eval_lisp("(local x 10) (print x) x")
eval_lisp("(if (== (+ 1 1) 2) (print \"foo\"))")
eval_lisp('{"a" (+ 1 3) "b" 2}')
