local M = {}

local function log(a, b)
    local file_path = "/Users/ligang/Downloads/log"
    local file, err = io.open(file_path, "a")  -- 关键："a" 追加模式
    file:write(a,',', b,"\n")
    file:close()
end

-- 1. 字符类型判定 (兼容 UTF-8 字节规律)
local function get_char_type(char)
    if not char or char == "" then return "other" end
    local byte = string.byte(char, 1)

    -- 英文数字 (ASCII: 0-9, A-Z, a-z)
    if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) then
        return "en_num"
    end

    -- 中文判定 (UTF-8 汉字首字节通常在 224-239 之间)
    -- 这里通过排除法识别汉字，确保标点符号被分类为 other
    if byte >= 224 and byte <= 239 then
        return "cn"
    end

    return "other"
end

-- 2. 提取 UTF-8 字符串的首尾字符 (原生正则实现)
local function get_first_char(s)
    return s:match("^[%z\1-\127]") or s:match("^[\194-\244][\128-\191]*") or ""
end

local function get_last_char(s)
    return s:match("[%z\1-\127]$") or s:match("[\194-\244][\128-\191]*$") or ""
end

-- 判定是否需要补空格
local function prepand_space(engine, last_text, current_text)
    if not last_text or last_text == "" or not current_text or current_text == "" then return false end
    local last_char = get_last_char(last_text)
    local first_char = get_first_char(current_text)
    
    local last_type = get_char_type(last_char)
    local curr_type = get_char_type(first_char)
    
    -- 判定：中+英 或 英+中
    if (last_type == "cn" and curr_type == "en_num") or (last_type == "en_num" and curr_type == "cn") then
        engine:commit_text(" ")
    end
end

local function is_visible_char(keycode)
    return keycode >= 32 and keycode <= 126
end

local function is_english_letter(keycode)
    return (keycode >= 65 and keycode <= 90) or (keycode >= 97 and keycode <= 122)
end

local function get_punc_char(env, key)
    local context = env.engine.context
    local config = env.engine.schema.config
    local keychar = string.char(key.keycode)
    
    -- 1. 首先判定是否为物理上的“可见键位” (ASCII 32-126)
    -- 如果是功能键（如 Return, F1），直接返回空或原名，避免后续误判为 en_num
    if not is_visible_char(keycode) then
        return ''
    end

    -- 2. 英文模式：直接返回 ASCII 字符
    if context:get_option("ascii_mode") then
        return keychar
    end

    -- 3. 中文模式：查标点映射表
    local shape = context:get_option("full_shape") and "full_shape" or "half_shape"
    local res = config:get_string("punctuator/" .. shape .. "/" .. keychar)
    
    if res then
        -- 过滤掉列表形式的配置，只取第一个字符
        return res:match("^[^%s]+") or res
    end

    -- 4. 兜底：既不是功能键，也没在标点表里（比如字母/数字），返回其 ASCII 字符
    return keychar
end

function M.func(key, env)
    local engine = env.engine
    local context = engine.context
    local krepr = key:repr()
    local keycode = key.keycode

    -- 过滤“松开按键”事件，防止逻辑触发两次
    if key:release() then return 2 end

    -- 获取当前是否为英文模式 (Shift 切换后的状态)
    local is_ascii = context:get_option("ascii_mode")

    -- 【场景 A】：非输入状态 (或是英文直输模式)(此时编码栏为空，处理直接上屏的 标点/数字/英文)
    -- 中文输入模式下，按下第一个字母，会触发该逻辑，候选词列表出现后不会继续触发
    -- 中文输入模式下，只要候选词列表不出现，就会继续触发
    -- 英文输入模式下，候选词列表永远不会出现，按下任何按键都会触发该逻辑
    -- 所以 context:is_composing() 应该理解成，候选词列表是否出现，这个分支处理的就是候选词列表未出现时的按键逻辑
    if not context:is_composing() then
        -- 中文输入状态按下第一个字母时，候选词列表还未出现，所以会进入该逻辑。不需要插入空格，不需要更新 env.last_text
        if not is_ascii and is_english_letter(keycode) then
            return 2
        end

        local current_str = get_punc_char(env, key)
        if current_str ~= "" then
            local last_str = env.last_text or ""
            prepand_space(engine, last_str, current_str)
            env.last_text = current_str
        else
            env.last_text = nil
        end

        return 2
    end

    -- 【场景 B】：输入状态 (正在输入拼音/编码)
    local is_return = (krepr == "Return")
    local is_space = (krepr == "space")
    local is_digit = krepr:match("^[0-9]$")
    local is_minus = (krepr == 'minus')
    -- TODO 发现还有一些别的标点也会触发上屏，可能大概也许也需要处理
    
    if is_return or is_space or is_digit or is_minus then
        local commit_text = ""
        if is_return then
            commit_text = context.input -- 回车上屏编码 (abc)
        elseif is_space then
            local cand = context:get_selected_candidate()
            if cand then commit_text = cand.text end
        elseif is_digit then
            local index = tonumber(krepr) - 1
            local target_cand = context:get_candidate_at(index)
            if target_cand then commit_text = target_cand.text end
        elseif is_minus then
            -- 如果按下了 - 号
            commit_text = context.input -- 先取 abc
        end

        if commit_text ~= "" then
            -- 提取语境：旧语境末尾 vs 新文本开头
            local last_str = env.last_text or ""

            prepand_space(engine, last_str, commit_text)

            if is_minus then
                -- 1. 先把 abc 上屏
                engine:commit_text(commit_text)
                -- 2. 清空当前输入上下文
                context:clear()
                -- 3. 把标点符号上屏
                engine:commit_text('-')
                -- 4. 更新语境为该标点
                env.last_text = '-'
                return 1 -- 告诉 Rime 我们已经处理完了，不要再去翻页了
            end

            -- 更新语境记录
            env.last_text = commit_text
        end
    end

    return 2
end

return M