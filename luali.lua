local PARENT = string.match((...) or "", "(.-)%.[^.]+$") or ""
local form = require(PARENT .. ".luali.form")
local parse = require(PARENT .. ".luali.parse")

local cons = form.cons

local function eval(s)
  print("--")
  print("eval:", s)
  parse.parse(
    coroutine.wrap(function() coroutine.yield(s) end),
    function(lisp_form)
      local code = form.to_lua(lisp_form)
      print("lua:", code)
      local f, error = loadstring(code)
      if error then
        print("load error:", error)
      else
        local result = {pcall(f)}
        if result[1] then
          print("return:", select(2, unpack(result)))
        else
          print("error:", select(2, unpack(result)))
        end
      end
      print()
  end)
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
eval("(fn (x y) (print (+ x y)))")
eval("(fn ())")
eval("(fn (x) (print x) (return (+ x 1)))")
eval("(fn () 123)")
eval("(if (== (+ 1 1) 2) \"two!\" \"other!\")")
eval("(if (== 1 2) (print \"foo\"))")
eval("(fn)")

eval("((fn (x y) (+ 100 (+ x y))) 12 34)")
eval("(if (== (+ 1 1) 2) \"two!\" \"other!\")")
