local M = {}

local function log(a, b)
    local file_path = "/Users/ligang/Downloads/log"
    local file, err = io.open(file_path, "a") -- 关键："a" 追加模式
    file:write(a, ',', b, "\n")
    file:close()
end

local function updateLastText(env, text)
    env.last_text = text
    -- env.last_time = rime_api.get_time_ms()
end

local function get_page_size(env)
    return env.engine.schema.config:get_int("menu/page_size")
end

local function get_candidate_at(env, index_in_current_page)
    local engine = env.engine
    -- 1. 获取当前页的起始位置 (Offset)
    -- 注意：不同版本的 librime-lua 获取 offset 的方式可能略有不同
    -- 最通用的方法是从 context.composition 的当前 segment 中获取
    local segment = engine.context.composition:back()
    local page_size = get_page_size(env)
    -- 计算当前页在全局候选列表中的起始索引
    -- selected_index 是当前高亮词的全局索引，通过它可以推算出当前页的起点
    local selected_candidate_index = segment.selected_index
    local current_page_no = math.ceil((selected_candidate_index + 1) / page_size)

    -- 2. 计算目标词在全局列表中的索引
    local target_index = (current_page_no - 1) * page_size + index_in_current_page - 1
        
    -- 3. 准备并获取候选词
    return target_index, segment.menu:get_candidate_at(target_index)
end

local function at_first_page(env)
    local engine = env.engine
    -- 1. 获取当前页的起始位置 (Offset)
    -- 注意：不同版本的 librime-lua 获取 offset 的方式可能略有不同
    -- 最通用的方法是从 context.composition 的当前 segment 中获取
    local segment = engine.context.composition:back()
    local page_size = get_page_size(env)
    -- 计算当前页在全局候选列表中的起始索引
    -- selected_index 是当前高亮词的全局索引，通过它可以推算出当前页的起点
    local selected_candidate_index = segment.selected_index
    local current_page_no = math.ceil((selected_candidate_index + 1) / page_size)

    return current_page_no == 1
end

local function at_last_page(env)
    local engine = env.engine
    -- 1. 获取当前页的起始位置 (Offset)
    -- 注意：不同版本的 librime-lua 获取 offset 的方式可能略有不同
    -- 最通用的方法是从 context.composition 的当前 segment 中获取
    local segment = engine.context.composition:back()
    local page_size = get_page_size(env)
    -- 计算当前页在全局候选列表中的起始索引
    -- selected_index 是当前高亮词的全局索引，通过它可以推算出当前页的起点
    local selected_candidate_index = segment.selected_index
    local current_page_no = math.ceil((selected_candidate_index + 1) / page_size)

    -- 获取 Menu 对象
    local menu = segment.menu
    -- 获得（已加载）候选词数量
    local loaded_candidate_count = menu:candidate_count()

    if loaded_candidate_count < current_page_no * page_size then
        return true
    elseif loaded_candidate_count > current_page_no * page_size then
        return false
    else 
        local prepare_count = menu:prepare(loaded_candidate_count + 1)
        if prepare_count > loaded_candidate_count then
            return false
        end
        return true
    end
end

-- TODO 理论上来说 last_text 只需要存储最后一个字符即可，把 last_text 改成 last_char
function M.init(env)
    env.last_text = ""
    env.last_time = 0

    -- 之前通过监听 space、return 等按键记录 last_text，鼠标点击上屏会记录不到。所以补充这个钩子注册。
    -- 核心：当 Rime 发生上屏动作时，自动触发这个回调
    -- 之前的逻辑也不能删，因为这个钩子是在上屏成功后执行的。
    -- 最下面的 updateLastText 不能删，因为手动调用 engine:commit_text 上屏不会触发 commit_notifier
    env.commit_notifier = env.engine.context.commit_notifier:connect(function(ctx)
        -- 这里拿到的就是真正上屏的字符串
        local text = ctx:get_commit_text()
        updateLastText(env, text)
    end)
end

function M.fini(env)
   env.commit_notifier:disconnect()
end

-- 1. 字符类型判定 (兼容 UTF-8 字节规律)
local function get_char_type(char)
    if not char or char == "" then
        return "other"
    end
    local byte = string.byte(char, 1)

    -- 1. 英文数字 (ASCII: 0-9, A-Z, a-z)
    if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) then
        return "en_num"
    end

    -- 2. 中文汉字判定 (UTF-8 三字节序列)
    if byte >= 224 and byte <= 239 and #char >= 3 then
        -- 计算 Unicode 码位 (UTF-8 解码逻辑)
        local b1 = byte
        local b2 = string.byte(char, 2)
        local b3 = string.byte(char, 3)
        local codepoint = ((b1 % 16) * 4096) + ((b2 % 64) * 64) + (b3 % 64)

        -- 常用汉字区间 [U+4E00, U+9FA5]
        -- 扩展区 A [U+3400, U+4DBF]
        if (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or (codepoint >= 0x3400 and codepoint <= 0x4DBF) then
            return "cn"
        end
    end

    -- 3. 其他（包括中文标点、英文标点、特殊符号）
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
local function prepend_space(env, last_text, current_text)
    -- local now = rime_api.get_time_ms()

    -- if now - env.last_time < 1000 then 
    if #last_text > 0 and #current_text > 0 then
        local last_char = get_last_char(last_text)
        local first_char = get_first_char(current_text)

        local last_type = get_char_type(last_char)
        local curr_type = get_char_type(first_char)
        -- 判定：中+英 或 英+中
        if (last_type == "cn" and curr_type == "en_num") or (last_type == "en_num" and curr_type == "cn") then
            env.engine:commit_text(" ")
        end
    end
    -- end
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
    local keycode = key.keycode

    -- 1. 首先判定是否为物理上的“可见键位” (ASCII 32-126)
    -- 如果是功能键（如 Return, F1），直接返回空或原名，避免后续误判为 en_num
    if not is_visible_char(keycode) then
        return ''
    end

    local keychar = string.char(keycode)

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
    if key:release() then
        return 2
    end

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
        if current_str ~= "" then -- 可见光标
            local last_str = env.last_text
            if last_str:match("^[0-9]$") and current_str == "。" then
                engine:commit_text('.')
                updateLastText(env, '.')
                return 1
            else
                prepend_space(env, last_str, current_str)
                updateLastText(env, current_str)
            end
        else -- 非可见光标
            -- 改变光标位置的需要把 env.last_text 置空
            -- 这些按键包括：
            -- 1. Tab、BackSpace、Return、Delete、Home、End
            -- 2. 方向键：Up 、Down 、Left 、Right，包括修饰键+方向键，如 Ctrl+Left，Super+Left，Shift+Left。其中 Ctrl+Left，Super+Left 只能捕获到 Ctrl 和 Super，没有 Left。Shift+Left 正常。只能妥协一下，用 find 方法了。只要按下 Super 就清空 last_text。
            -- 3. 快捷键：全选 Command + A ，删除当前行 Command + X
            if krepr == "Tab" or krepr == "BackSpace" or krepr == "Return" or krepr == "Delete" or krepr == "Home" or
                krepr == "End" or krepr:find("Up") or krepr:find("Down") or krepr:find("Left") or krepr:find("Right") then
                updateLastText(env, '')
            end
        end

        return 2
    end

    -- 【场景 B】：输入状态 (正在输入拼音/编码)
    local is_return = (krepr == "Return")
    local is_space = (krepr == "space")
    local is_digit = krepr:match("^[0-9]$")
    local is_minus = (krepr == 'minus')
    local is_comma = (krepr == "comma")
    local is_period = (krepr == "period")
    -- TODO 发现还有一些别的标点也会触发上屏，可能大概也许也需要处理

    local commit_text = ""
    local cand_index

    if is_return then
        commit_text = context.input -- 回车上屏编码 (abc)
    end
    
    if is_space then
        local cand = context:get_selected_candidate()
        if cand then
            commit_text = cand.text
        end
    end

    if is_digit then
        local digit = tonumber(krepr)

        if digit == 0 or digit > get_page_size(env) then
            commit_text = context.input .. digit
        else
            local target_index, target_cand = get_candidate_at(env, digit)
            cand_index = target_index
            if target_cand then
                commit_text = target_cand.text
            else
                commit_text = context.input .. krepr
            end
        end
    end

    if is_minus then
        commit_text = context.input .. '-'
    end

    if is_comma then
        if at_first_page(env) then
            local cand = context:get_selected_candidate()
            if cand then
                commit_text = cand.text .. '，'
            end
        end
    end

    -- if is_period then
    --     if at_last_page(env) then
    --         local cand = context:get_selected_candidate()
    --         if cand then
    --             commit_text = cand.text .. '。'
    --         end
    --     end
    -- end

    if commit_text ~= "" then
        prepend_space(env, env.last_text, commit_text)

        if is_space then
            context.confirm_current_selection()
        elseif is_digit then
            context.select(cand_index)
        else
            engine:commit_text(commit_text)
            context:clear()
        end

        updateLastText(env, commit_text)
        return 1
    end

    return 2
end

return M
