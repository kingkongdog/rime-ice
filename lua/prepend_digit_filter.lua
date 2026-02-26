-- number_first.lua
-- 检测输入是否是 1-9，并在第一位插入该数字

local function filter(input, env)
    local context = env.engine.context
    local input_str = context.input

    -- 使用正则判断是否为纯数字
    if string.match(input_str, "^%d$") then
        -- 构造一个候选词：类型为 "number"，内容为输入字符串，注释为 "数字"
        local cand = Candidate("raw", 0, #input_str, input_str, "")
        yield(cand)
        
        -- 之后正常输出其他的候选词
    end

    for cand in input:iter() do
        yield(cand)
    end
end

return filter
