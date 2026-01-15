local M = {}

function M.func(key, env)
  local engine = env.engine
  local context = engine.context
  local code = key.keycode

  if code >= 48 and code <= 57 then
    -- 这里不要用 key:repr()，否则可能推入 Shift+1
    -- context:push_input(string.char(code))
    context:push_input("1")
    return 1
  end

  return 2
end

return M