task.spawn(function()
--[[ ============================================================================
     ZABOTA MULTI DUMP PRO  —  универсальный дампер под ЛЮБЫЕ плейсы и режимы
     ============================================================================ ]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RepStorage        = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer

-- ── Буфер обмена ─────────────────────────────────────────────────────────────
local function toClipboard(text)
    local fns = { setclipboard, syn and syn.write_clipboard, toclipboard, Clipboard and Clipboard.set }
    for _, f in ipairs(fns) do
        if type(f) == "function" and pcall(f, text) then return true end
    end
    return false
end

-- ── Запись на Рабочий стол / Документы / workspace ────────────────────────────
local function saveFile(name, text)
    if type(writefile) ~= "function" then return false, "writefile недоступен" end

    if type(makefolder) == "function" then
        pcall(makefolder, "dumps")
    end

    local paths = {}
    
    -- 1. Выход из песочницы инжектора (Xeno/KRNL)
    paths[#paths + 1] = "../../Desktop/" .. name
    paths[#paths + 1] = "../../../Desktop/" .. name
    paths[#paths + 1] = "../Desktop/" .. name

    -- 2. Системные профили Windows
    if type(os.getenv) == "function" then
        local user = os.getenv("USERPROFILE")
        if user and user ~= "" then
            paths[#paths + 1] = user .. "\\Desktop\\" .. name
            paths[#paths + 1] = user .. "\\OneDrive\\Desktop\\" .. name
            paths[#paths + 1] = user .. "\\Documents\\" .. name
        end
    end

    -- 3. Внутренняя папка workspace
    paths[#paths + 1] = "dumps/" .. name
    paths[#paths + 1] = name

    for _, path in ipairs(paths) do
        local ok = pcall(writefile, path, text)
        if ok then
            if type(isfile) == "function" then
                local existsOk, exists = pcall(isfile, path)
                if existsOk and exists then return true, path end
            else
                return true, path
            end
        end
    end

    return false, "Ошибка записи файла"
end

-- ── Умный автопоиск папок в любом режиме ──────────────────────────────────────
local function findSmartFolder(keywords)
    for _, root in ipairs({RepStorage, workspace, game:GetService("ReplicatedFirst")}) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("Folder") or obj:IsA("Model") or obj:IsA("Configuration") then
                local name = obj.Name:lower()
                for _, kw in ipairs(keywords) do
                    if name:find(kw) then return obj end
                end
            end
        end
    end
    return nil
end

-- ── Рекурсивный дамп инстансов ───────────────────────────────────────────────
local function dumpInstance(root, opts)
    opts = opts or {}
    local maxDepth  = opts.depth or 6
    local maxNodes  = opts.maxNodes or 25000
    local wantProps = opts.props ~= false
    local wantAttrs = opts.attrs ~= false
    local smart     = opts.smart == true
    local lines, count, truncated, hidden = {}, 0, false, 0

    local SMART_KW = {
        remote = true, sound = true, anim = true, weapon = true, gun = true,
        knife = true, tool = true, camera = true, gui = true, ui = true,
        player = true, char = true, enemy = true, item = true, skin = true,
        controller = true, module = true, data = true, config = true
    }

    local function isInteresting(inst)
        local cls = inst.ClassName
        if cls:find("Remote") or cls:find("Bindable") or cls == "Sound" or cls == "Animation"
           or cls == "ModuleScript" or cls == "LocalScript" or cls == "Script"
           or cls == "Tool" or cls == "Humanoid" or cls == "Animator" then return true end
        if inst:IsA("ValueBase") then return true end
        
        local name = inst.Name:lower()
        for kw in pairs(SMART_KW) do
            if name:find(kw) then return true end
        end
        return false
    end

    local function getProps(inst)
        if not wantProps then return "" end
        local props = {}
        pcall(function()
            if inst:IsA("BasePart") then
                props[#props + 1] = string.format("Size=(%.2f,%.2f,%.2f)", inst.Size.X, inst.Size.Y, inst.Size.Z)
            end
            if inst:IsA("MeshPart") then
                props[#props + 1] = "MeshId=" .. tostring(inst.MeshId):sub(1, 24)
                if inst.TextureID ~= "" then props[#props + 1] = "Tex=" .. tostring(inst.TextureID):sub(1, 20) end
            elseif inst:IsA("SurfaceAppearance") then
                if inst.ColorMap ~= "" then props[#props + 1] = "ColorMap=" .. tostring(inst.ColorMap):sub(1, 22) end
            elseif inst:IsA("Motor6D") or inst:IsA("Weld") then
                props[#props + 1] = string.format("Part0:%s -> Part1:%s", tostring(inst.Part0), tostring(inst.Part1))
            elseif inst:IsA("Animation") then
                props[#props + 1] = "AnimId=" .. tostring(inst.AnimationId)
            elseif inst:IsA("Sound") then
                props[#props + 1] = "SoundId=" .. tostring(inst.SoundId)
            elseif inst:IsA("ValueBase") then
                props[#props + 1] = "Val=" .. tostring(inst.Value)
            elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
                props[#props + 1] = "⚡ REMOTE"
            end
        end)

        if wantAttrs then
            pcall(function()
                local a = inst:GetAttributes()
                local t = {}
                for k, v in pairs(a) do t[#t + 1] = k .. "=" .. tostring(v) end
                if #t > 0 then props[#props + 1] = "{" .. table.concat(t, ", ") .. "}" end
            end)
        end

        return #props > 0 and ("  [" .. table.concat(props, " | ") .. "]") or ""
    end

    local function walk(inst, depth)
        if truncated then return end
        count = count + 1
        if count > maxNodes then
            truncated = true
            lines[#lines + 1] = "... [⚠ ОБРЕЗАНО: превышен лимит " .. maxNodes .. " узлов]"
            return
        end

        local cls, nm = "?", "?"
        pcall(function() cls = inst.ClassName; nm = inst.Name end)
        lines[#lines + 1] = string.format("%s[%s] %s%s", string.rep("│  ", depth), cls, nm, getProps(inst))

        local kids = {}
        pcall(function() kids = inst:GetChildren() end)

        if depth >= maxDepth then
            if #kids > 0 then
                hidden = hidden + #kids
                lines[#lines + 1] = string.rep("│  ", depth + 1) .. "… (" .. #kids .. " детей скрыто по лимиту глубины)"
            end
            return
        end

        if not smart then
            for _, c in ipairs(kids) do walk(c, depth + 1) end
            return
        end

        local keep, drop = {}, {}
        for _, c in ipairs(kids) do
            if isInteresting(c) or #c:GetChildren() > 0 then
                keep[#keep + 1] = c
            else
                local ccls = c.ClassName
                drop[ccls] = (drop[ccls] or 0) + 1
            end
        end

        for _, c in ipairs(keep) do walk(c, depth + 1) end
        for ccls, countGrp in pairs(drop) do
            if countGrp >= 3 then
                hidden = hidden + countGrp
                lines[#lines + 1] = string.rep("│  ", depth + 1) .. "▸ " .. countGrp .. " × [" .. ccls .. "] — скрыто (декор)"
            end
        end
    end

    walk(root, 0)
    return table.concat(lines, "\n"), count, truncated, hidden
end

-- ── Ремоуты (вся игра) ───────────────────────────────────────────────────────
local function dumpRemotes()
    local out, n = {}, 0
    local visited = 0
    local function pathOf(inst)
        local parts, cur = {}, inst
        while cur and cur ~= game do
            parts[#parts + 1] = cur.Name
            cur = cur.Parent
        end
        local rev = {}
        for i = #parts, 1, -1 do rev[#rev + 1] = parts[i] end
        return table.concat(rev, ".")
    end

    local function walk(inst, depth)
        if visited >= 60000 then return end
        visited = visited + 1
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
            n = n + 1
            out[#out + 1] = string.format("[%s] %s", inst.ClassName, pathOf(inst))
            return
        end
        if depth >= 12 then return end
        for _, k in ipairs(inst:GetChildren()) do walk(k, depth + 1) end
    end
    walk(game, 0)
    return table.concat(out, "\n"), n
end

-- ── Шапка дампа ───────────────────────────────────────────────────────────────
local function buildDump(label, root, opts)
    local body, count, truncated, hidden = dumpInstance(root, opts)
    local h = {
        "===== ZABOTA MULTI DUMP PRO =====",
        "Цель:      " .. label,
        "PlaceId:   " .. tostring(game.PlaceId),
        "JobId:     " .. tostring(game.JobId),
        "Дата:      " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Узлов:     " .. count .. (hidden > 0 and (" (мусора скрыто: " .. hidden .. ")") or ""),
        "Глубина:   " .. tostring(opts.depth),
        "=================================",
        "",
    }
    return table.concat(h, "\n") .. body, count, truncated, hidden
end

-- ── ЦЕЛИ ДАМПА ДЛЯ ВСЕХ РЕЖИМОВ ─────────────────────────────────────────────
local TARGETS = {
    { key = "remotes",     title = "📡 ТОЛЬКО РЕМОУТЫ (вся игра)", depth = 12, special = "remotes",
      get = function() return game end },
      
    { key = "weapons",     title = "🔫 Оружие / Предметы (Автопоиск)", depth = 8,
      get = function() return findSmartFolder({"weapon", "gun", "item", "tool", "armory"}) or RepStorage:FindFirstChild("Assets") end },

    { key = "controllers", title = "🕹 Контроллеры / Модули (Автопоиск)", depth = 6,
      get = function() return findSmartFolder({"controller", "module", "client", "service"}) or RepStorage:FindFirstChild("Controllers") end },

    { key = "anims",       title = "🎬 Анимации (Автопоиск)", depth = 6,
      get = function() return findSmartFolder({"anim", "animation"}) end },

    { key = "skins",       title = "🎨 Скины / Текстуры (Автопоиск)", depth = 7,
      get = function() return findSmartFolder({"skin", "texture", "cosmetic"}) end },

    { key = "camera_vm",   title = "🎥 Camera (Вьюмодель в руках)", depth = 8,
      get = function() return workspace.CurrentCamera end },

    { key = "replicated",  title = "📦 ReplicatedStorage (Полный)", depth = 5,
      get = function() return RepStorage end },

    { key = "characters",  title = "👤 Персонажи / NPC (Workspace)", depth = 6,
      get = function() return workspace:FindFirstChild("Characters") or workspace:FindFirstChild("Players") or workspace:FindFirstChild("NPCs") end },

    { key = "playergui",   title = "🖥 PlayerGui (Интерфейсы UI)", depth = 7,
      get = function() return LocalPlayer:FindFirstChild("PlayerGui") end },

    { key = "fullgame",    title = "🌐 ВСЯ ИГРА (Game, обзорно)", depth = 3,
      get = function() return game end },
}

-- ── ИНТЕРФЕЙС GUI ─────────────────────────────────────────────────────────────
local depth = 6
local wantAttrs, wantProps, smart = true, true, true

if game:GetService("CoreGui"):FindFirstChild("ZABOTA_MultiDump") then
    game:GetService("CoreGui").ZABOTA_MultiDump:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "ZABOTA_MultiDump"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(330, 490)
main.Position = UDim2.new(0.5, -165, 0.5, -245)
main.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(70, 130, 255)
stroke.Thickness = 1.5

-- Верхняя панель
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 36)
bar.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
bar.BorderSizePixel = 0
bar.Parent = main
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0); title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 13.5
title.TextColor3 = Color3.fromRGB(240, 244, 255); title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "ZABOTA MULTI DUMP"; title.Parent = bar

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(24, 24); close.Position = UDim2.new(1, -30, 0, 6)
close.BackgroundColor3 = Color3.fromRGB(200, 50, 50); close.Text = "✕"
close.TextColor3 = Color3.new(1, 1, 1); close.Font = Enum.Font.GothamBold; close.TextSize = 12
close.Parent = bar; Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)
close.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Перетаскивание
do
    local drag, startPos, startInput
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; startPos = main.Position; startInput = i.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local delta = i.Position - startInput
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)
end

-- Статус
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 42); status.Position = UDim2.fromOffset(10, 44)
status.BackgroundColor3 = Color3.fromRGB(26, 30, 40); status.BorderSizePixel = 0
status.Font = Enum.Font.GothamMedium; status.TextSize = 11.5; status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(180, 190, 205)
status.Text = "Готов. Выбери цель для дампа (авто-сохранение + буфер обмена)."
status.Parent = main; Instance.new("UICorner", status).CornerRadius = UDim.new(0, 8)

-- Скролл целей
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -96); scroll.Position = UDim2.fromOffset(10, 92)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = main
local list = Instance.new("UIListLayout", scroll)
list.Padding = UDim.new(0, 5)

-- Исполнение дампа
local busy = false
local function runDump(target)
    if busy then return end
    busy = true
    status.TextColor3 = Color3.fromRGB(255, 210, 90)
    status.Text = "⏳ Сбор данных: " .. target.title .. "..."
    task.wait(0.05)

    local ok, res = pcall(function()
        local stamp = os.date("%Y-%m-%d_%H-%M-%S")
        local fname = "dump_" .. target.key .. "_" .. stamp .. ".txt"
        local text, count = "", 0

        if target.special == "remotes" then
            text, count = dumpRemotes()
            text = "===== ZABOTA REMOTES DUMP =====\nДата: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\nВсего: " .. count .. "\n===============================\n\n" .. text
        else
            local root = target.get()
            if not root then return { err = "Папка/объект не найден в этом режиме" } end
            text, count = buildDump(target.title, root, { depth = target.depth or depth, props = wantProps, attrs = wantAttrs, smart = smart })
        end

        local saved, where = saveFile(fname, text)
        local copied = toClipboard(text)
        return { saved = saved, where = where, copied = copied, count = count, fname = fname }
    end)

    if not ok or res.err then
        status.TextColor3 = Color3.fromRGB(255, 80, 80)
        status.Text = "❌ " .. tostring(res and res.err or res)
    else
        status.TextColor3 = Color3.fromRGB(110, 240, 140)
        local loc = res.saved and res.where or "workspace"
        status.Text = string.format("✅ Узлов: %d | 📋 Буфер скопирован!\n📁 %s", res.count, loc)
    end
    busy = false
end

for _, t in ipairs(TARGETS) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -4, 0, 34)
    btn.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
    btn.Text = "  " .. t.title
    btn.TextColor3 = Color3.fromRGB(235, 240, 250)
    btn.Font = Enum.Font.GothamMedium; btn.TextSize = 12; btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = scroll; Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(function() runDump(t) end)
end
end)
