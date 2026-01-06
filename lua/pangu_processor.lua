local M = {}

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

function M.func(key, env)
    local engine = env.engine
    local context = engine.context
    local k = key:repr()

    -- 过滤“松开按键”事件，防止逻辑触发两次
    if key:release() then return 2 end

    -- 获取当前是否为英文模式 (Shift 切换后的状态)
    local is_ascii = context:get_option("ascii_mode")

    -- 【场景 A】：非输入状态 (或是英文直输模式)(此时编码栏为空，处理直接上屏的 标点/数字/英文)
    if not context:is_composing() then
        -- 1. 在中文模式下，字母 [a-zA-Z] 是编码种子，不要覆写语境，也不要触发空格
        -- (正则：只有当它是单个字母，且不在英文模式时，才拦截)
        -- (注意：此处不包含数字，因为数字在非输入状态通常直接上屏)
        if not is_ascii and k:match("^[a-zA-Z]$") then
            return 2
        end

        -- 2. 过滤掉纯修饰键本身 (Shift, Control, Alt 等)
        -- 按下这些键不产生字符，也不应该清空语境
        if k:find("Shift") or k:find("Control") or k:find("Alt") then
            return 2
        end

        -- 3. 判定可见字符 (标点、数字、英文模式下的字母)
        local is_visible = (k:len() == 1 and string.byte(k) > 32) or (string.byte(k, 1) > 127)
        
        if is_visible then
            -- 提取旧语境末尾字符
            local last_char = get_last_char(env.last_text or "")
            local type_left = get_char_type(last_char)
            local type_right = get_char_type(k) -- 当前按下的键

            -- 如果发生 中+英 或 英+中 冲突，补空格
            if (type_left == "cn" and type_right == "en_num") or 
               (type_left == "en_num" and type_right == "cn") then
                engine:commit_text(" ")
            end

            -- 更新全局变量为当前按下的字符 (作为新语境)
            env.last_text = k
        else
            -- 真正的功能键按下（如非输入状态下的 Return 换行、Esc、BackSpace、Tab）
            -- 按照方案：彻底清空语境
            env.last_text = nil
        end
        return 2
    end

    -- 【场景 B】：输入状态 (正在输入拼音/编码)
    local is_return = (k == "Return")
    local is_space = (k == "space")
    local is_digit = k:match("^[0-9]$")

    if is_return or is_space or is_digit then
        local commit_text = ""
        if is_return then
            commit_text = context.input -- 回车上屏编码 (abc)
        elseif is_space then
            local cand = context:get_selected_candidate()
            if cand then commit_text = cand.text end
        elseif is_digit then
            local index = tonumber(k) - 1
            local target_cand = context:get_candidate_at(index)
            if target_cand then commit_text = target_cand.text end
        end

        if commit_text ~= "" then
            -- 提取语境：旧语境末尾 vs 新文本开头
            local last_str = env.last_text or ""
            local last_char = get_last_char(last_str)
            local first_char = get_first_char(commit_text)

            local type_left = get_char_type(last_char)
            local type_right = get_char_type(first_char)

            -- 判定补空格
            if (type_left == "cn" and type_right == "en_num") or 
               (type_left == "en_num" and type_right == "cn") then
                engine:commit_text(" ")
            end

            -- 更新语境记录
            env.last_text = commit_text
        end
    end

    return 2
end

return M