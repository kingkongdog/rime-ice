local M = {}

function M.func(input, env)
    local has_cand = false
    
    -- 尝试获取第一个候选词
    for cand in input:iter() do
        yield(cand)
        has_cand = true
    end

    -- 如果循环结束了 has_cand 仍为 false，说明原本没有候选词
    if not has_cand then
        -- context.input 包含了当前的编码
        local code = env.engine.context.input
        -- 构造一个简单的候选词：类型为 "raw"，起始位置 0，结束位置为输入长度
        yield(Candidate("raw", 0, #code, code, ""))
    end
end

return M