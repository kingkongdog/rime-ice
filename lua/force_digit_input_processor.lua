local M = {}

function M.init(env)
    env.last_input_time_ms = 0
end

local function to_t9_number(char)
  local t9_map = {
    A = "2", B = "2", C = "2",
    D = "3", E = "3", F = "3",
    G = "4", H = "4", I = "4",
    J = "5", K = "5", L = "5",
    M = "6", N = "6", O = "6",
    P = "7", Q = "7", R = "7", S = "7",
    T = "8", U = "8", V = "8",
    W = "9", X = "9", Y = "9", Z = "9",
  }
  return t9_map[char:upper()]
end

function M.func(key, env)
  local is_ascii = env.engine.context:get_option("ascii_mode")
  if is_ascii then
    return 2
  end

  if key:release() then
    return 1
  end

  if key:ctrl() then
    return 2
  end
  
  local engine = env.engine
  local context = engine.context
  local code = key.keycode
  local input_time_ms = rime_api.get_time_ms()
  local delta = input_time_ms - env.last_input_time_ms

  -- 解决在输入拼音过程中偶现数字直接上屏问题
  -- 解决在输入拼音过程中偶现按一个键进入 input 两次的问题
  -- 小于 70 认为是同文 bug 导致的二次触发，https://gemini.google.com/share/b0c0711a3ce4
  if code >= 48 and code <= 57 then
    local char = string.char(code)
    if delta > 30 then
      -- 这里不要用 key:repr()，否则可能推入 Shift+1
      context:push_input(char)
      env.last_input_time_ms = input_time_ms
    else
      context:push_input("")
    end
    return 1
  end

  -- 解决在快速输入拼音过程中，触发 swipe 事件，导致进入 input 的不是数字是字母的问题
  -- 输入数字过程是比较快的，真正 swipe 的时候是比较慢的，以 250ms 为界。
  if (code >= 97 and code <= 122) or (code >= 65 and code <= 90) then
    local char = string.char(code)
    if delta > 30 then
      if delta < 250 then
        context:push_input(to_t9_number(char))
      else
        -- 这里不要用 key:repr()，否则可能推入 Shift+1
        context:push_input(char)
      end
      env.last_input_time_ms = input_time_ms
    else
      context:push_input("")
    end
    return 1
  end

  return 2
end

return M