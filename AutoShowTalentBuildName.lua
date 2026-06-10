local AddonName, ns = ...
ns.db = {}

local DEFAULTS = {
    point    = "CENTER",
    x        = 0,
    y        = 200,
    fontSize = 14,
    showSpec = false,
}

-- ── label frame ───────────────────────────────────────────────────────────────

local label = CreateFrame("Frame", "AutoShowTalentBuildNameFrame", UIParent)
label:SetSize(200, 30)
label:SetClampedToScreen(true)

local text = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("TOPLEFT")
text:SetJustifyH("LEFT")
text:SetJustifyV("TOP")

local function ResizeToText()
    label:SetSize(math.max(text:GetStringWidth(), 10), math.max(text:GetStringHeight(), 10))
end

local function SetFontSize(size)
    local fontPath, _, fontFlags = text:GetFont()
    text:SetFont(fontPath, size, fontFlags)
    ResizeToText()
end

local function GetSpecID()
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        return PlayerUtil.GetCurrentSpecID()
    end
    local idx = GetSpecialization()
    return idx and select(1, GetSpecializationInfo(idx))
end

local function GetSpecName()
    local idx = GetSpecialization()
    if idx then
        return select(2, GetSpecializationInfo(idx))
    end
end

local function UpdateLabel()
    local buildName = ""

    -- GetLastSelectedSavedConfigID returns the named loadout ("m+ SP"),
    -- unlike GetActiveConfigID which returns the working/committed config
    -- that is always named after the spec ("Brewmaster").
    local specID = GetSpecID()
    if specID and C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
        local savedID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
        if savedID and C_Traits and C_Traits.GetConfigInfo then
            local info = C_Traits.GetConfigInfo(savedID)
            if info and type(info.name) == "string" and info.name ~= "" then
                buildName = info.name
            end
        end
    end

    -- Fallback: active config name (will be the spec name if no named loadout is selected)
    if buildName == "" and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID and C_Traits and C_Traits.GetConfigInfo then
            local info = C_Traits.GetConfigInfo(configID)
            if info and type(info.name) == "string" and info.name ~= "" then
                buildName = info.name
            end
        end
    end

    local displayText = buildName
    if ns.db.showSpec then
        local specName = GetSpecName()
        if specName and specName ~= "" then
            if buildName ~= "" and buildName ~= specName then
                displayText = specName .. "\n" .. buildName
            else
                displayText = specName
            end
        end
    end

    text:SetText(displayText)
    ResizeToText()
end

-- ── Edit Mode integration (LibEditMode) ───────────────────────────────────────

local function SetupEditMode()
    local lib = LibStub and LibStub("LibEditMode", true)
    if not lib then return end

    lib:AddFrame(label, function(frame, layoutName, point, x, y)
        ns.db.point = point
        ns.db.x     = x
        ns.db.y     = y
    end, { point = DEFAULTS.point, x = DEFAULTS.x, y = DEFAULTS.y }, "AutoShowTalentBuildName")

    lib:AddFrameSettings(label, {
        {
            kind      = lib.SettingType.Checkbox,
            name      = "Show Spec",
            desc      = "Show specialization name above the talent build name",
            default   = DEFAULTS.showSpec,
            get = function() return ns.db.showSpec end,
            set = function(_, value)
                ns.db.showSpec = value
                UpdateLabel()
            end,
        },
        {
            kind      = lib.SettingType.Slider,
            name      = "Font Size",
            desc      = "Size of the talent build name text",
            default   = DEFAULTS.fontSize,
            minValue  = 6,
            maxValue  = 72,
            valueStep = 1,
            get = function() return ns.db.fontSize end,
            set = function(_, value)
                ns.db.fontSize = value
                SetFontSize(value)
            end,
        },
    })
end

-- ── event handler ─────────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= AddonName then return end
        AutoShowTalentBuildNameDB = AutoShowTalentBuildNameDB or CopyTable(DEFAULTS)
        ns.db = AutoShowTalentBuildNameDB
        for k, v in pairs(DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        label:ClearAllPoints()
        label:SetPoint(ns.db.point or "CENTER", UIParent, ns.db.point or "CENTER", ns.db.x, ns.db.y)
        SetFontSize(ns.db.fontSize)
        C_Timer.After(1, UpdateLabel)  -- talent data loads from server after PLAYER_LOGIN
        SetupEditMode()
        self:RegisterEvent("TRAIT_CONFIG_UPDATED")
        self:RegisterEvent("PLAYER_TALENT_UPDATE")
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
        -- GetLastSelectedSavedConfigID isn't updated yet when these fire;
        -- wait a short moment for the talent system to settle (same pattern as NaowhQOL)
        C_Timer.After(0.5, UpdateLabel)
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.5, UpdateLabel)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, UpdateLabel)
    end
end)

-- ── slash command ─────────────────────────────────────────────────────────────

SLASH_AUTOSHOWTALENTBUILDNAME1 = "/astbn"
SlashCmdList["AUTOSHOWTALENTBUILDNAME"] = function(msg)
    local cmd, val = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "size" then
        local size = tonumber(val)
        if size and size >= 6 and size <= 72 then
            ns.db.fontSize = size
            SetFontSize(size)
        else
            print("|cffff9900AutoShowTalentBuildName:|r /astbn size <6-72>")
        end
    else
        print("|cffff9900AutoShowTalentBuildName:|r Commands:")
        print("  /astbn size <6-72>  — set font size")
        print("  (use Edit Mode to move the frame and adjust font size)")
    end
end
