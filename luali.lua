local form = require("luali.form")
local parse = require("luali.parse")
local util = require("luali.util")

local cons = form.cons

local function eval(s)
  print("--")
  print("lisp:", s)
  local env = form.env()
  parse.parse(
    coroutine.wrap(function() coroutine.yield(s) end),
    function(lisp_form)
      local code = form.compile(lisp_form, env)
      print("---- compile and eval")
      print("lua:", code)
      local f, error = loadstring("return " .. code)
      if error then
        print("load error:", error)
      else
        local result = {pcall(f)}
        print(result[1] and "return:" or "error:")
        util.dump(select(2, unpack(result)))
      end
  end)
  env = form.env()
  parse.parse(
    coroutine.wrap(function() coroutine.yield(s) end),
    function(lisp_form)
      print("---- eval lisp")
      local result = {pcall(function() return form.eval(lisp_form, env) end)}
      print(result[1] and "return:" or "error:")
      util.dump(select(2, unpack(result)))
    end
  );
  print()
end

eval("  hoge piyo foo")
eval("hoge   ")
eval("true")
eval("false")
eval("nil")
eval("print")
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
eval('{"a" (+ 1 3) "b" 2}')
eval('["a" "b" "c"]')
eval("((fn (x y) (print (+ x y))))")
eval("((fn ()))")
eval("((fn (x) (print x) (+ x 1)))")
eval("((fn () 123))")
eval("(if (== (+ 1 1) 2) \"two!\" \"other!\")")
eval("(if (== (+ 1 2) 2) \"two!\" \"other!\")")
eval("(if (== 1 2) (print \"foo\"))")
eval("((fn))")
eval("((fn (x y) (+ 100 (+ x y))) 12 34)")
eval("(if (== (+ 1 1) 2) \"two!\" \"other!\")")
eval("(math.pow (+ 8 4) 3)")
eval("((. math \"pow\") 12 3)")
eval("(print (. [10 20 30] 2))")
eval("(print x) ((fn (x y) (+ 100 (+ x y))) 12 34) (print x)")
eval("(local x 10) (print x) x")
eval("(if (== (+ 1 1) 2) (print \"foo\"))")
