local function english_filter(input, env)
    local context = env.engine.context
    local input_str = context.input

    -- 包含字母
    if string.match(input_str, "%a") and #input_str < 2 then
        local cand = Candidate("raw", 0, #input_str, input_str, "")
        yield(cand)
    else
        for cand in input:iter() do
            yield(cand)
        end
    end
end

return english_filter