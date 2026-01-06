-- pangu_processor: 中英文间自动加空格（上屏瞬间触发，不影响候选框视觉）
local M = {}

-- 判断字符类型
local function get_char_type(char)
    if not char or char == "" then return "other" end
    local byte = string.byte(char, 1)
    -- 英文和数字 (ASCII)
    if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) then
        return "en_num"
    end
    -- 中文 (UTF-8 首字节 > 127)
    if byte > 127 then return "cn" end
    return "other"
end

local function log(a, b)
    local file_path = "/Users/ligang/Downloads/log"
    local file, err = io.open(file_path, "a")  -- 关键："a" 追加模式
    file:write(a,',', b,"\n")
    file:close()
end

-- 获取首/尾字符 (兼容 UTF-8)
local function get_first_char(s) return s:match("^[%z\1-\127]") or s:match("^[\194-\244][\128-\191]*") or "" end
local function get_last_char(s) return s:match("[%z\1-\127]$") or s:match("[\194-\244][\128-\191]*$") or "" end

-- 判定是否需要补空格
local function needs_space(last_text, current_text)
    log("last_text:", last_text)
    log("current_text:", current_text)
    if not last_text or last_text == "" or not current_text or current_text == "" then return false end
    local last_char = get_last_char(last_text)
    local first_char = get_first_char(current_text)
    
    local last_type = get_char_type(last_char)
    local curr_type = get_char_type(first_char)
    
    -- 判定：中+英 或 英+中
    return (last_type == "cn" and curr_type == "en_num") or (last_type == "en_num" and curr_type == "cn")
end

function M.func(key, env)
    local engine = env.engine
    local context = engine.context

    -- 仅在正在输入（有编码）时处理
    if not context:is_composing() then return 2 end

    -- 定义会导致上屏的按键：空格、回车、数字选词(1-9)
    local k = key:repr()
    local is_commit_key = (k == "space" or k == "Return" or k:match("^[0-9]$"))

    if is_commit_key then
        local history = context.commit_history
        local last_text = history:empty() and "" or history:latest_text()
        
        -- 确定即将上屏的文本内容
        local commit_text = ""
        local cand = context:get_selected_candidate()
        
        if k:match("^[0-9]$") then
            -- 如果是数字键选词，获取对应序号的候选词
            local index = tonumber(k) - 1
            local list = context:get_candidates()
            -- 注意：这里只能获取当前页的候选
            local target_cand = context:get_candidate_at(index)
            if target_cand then commit_text = target_cand.text end
        elseif k == "Return" then
            -- 回车上屏编码
            commit_text = context:get_commit_text()
        elseif k == "space" then
            -- 空格上屏选中的词
            if cand then commit_text = cand.text end
        end

        -- 如果满足加空格条件，先上屏一个空格
        if commit_text ~= "" and needs_space(last_text, commit_text) then
            engine:commit_text(" ")
        end
    end

    return 2 -- kNoop: 让 Rime 继续处理原本的按键逻辑
end

return M