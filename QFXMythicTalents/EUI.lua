-- QFXMythicTalents EllesmereUI skin bridge (developer guide: SKINNING_API.md in
-- the EllesmereUI addon). EUI invokes the registered function once per session
-- with a skinning facade S built for this addon; every primitive is idempotent
-- and follows the user's live theme, so frames created later are handed over as
-- they appear. When EllesmereUI is missing or skinning for this addon is off,
-- nothing here runs and the addon keeps its own visuals.

local ADDON_NAME, ns = ...

local EUI = _G.EllesmereUI
local skin

-- frame -> { frame = frame, kind = "..." }
local entries = setmetatable({}, { __mode = "k" })
local looksCallbacks = {}

local function ApplyEntry(entry)
    if not skin then
        return
    end
    local frame = entry.frame
    if not frame then
        return
    end

    local kind = entry.kind
    if kind == "shell" or kind == "panel" then
        -- EUI paints its own backdrop; drop the addon's SetBackdrop art first
        -- so it cannot show through the house panel.
        if frame.SetBackdrop then
            frame:SetBackdrop(nil)
        end
    end

    if kind == "shell" then
        if skin.Shell then
            skin.Shell(frame)
        end
    elseif kind == "panel" then
        if skin.Panel then
            skin.Panel(frame)
        end
    elseif kind == "button" then
        if skin.Button then
            skin.Button(frame)
        end
    elseif kind == "buttonLabel" then
        if skin.Button then
            skin.Button(frame)
        end
        if skin.StateButtonLabel then
            skin.StateButtonLabel(frame)
        end
    elseif kind == "close" then
        if skin.CloseButton then
            skin.CloseButton(frame)
        end
    elseif kind == "scrollbar" then
        if skin.ScrollBar then
            skin.ScrollBar(frame)
        end
    elseif kind == "font" then
        if skin.Font then
            skin.Font(frame)
        end
    end
end

-- Register (or re-register) a frame for EUI styling. Safe to call before EUI
-- has dispatched the facade: the entry is queued and painted as soon as the
-- facade arrives. Re-registering the same frame is idempotent (EUI primitives
-- bail after one lookup), so style-refresh paths may call this freely.
function ns.RegisterEUISkin(frame, kind)
    if not frame or not kind then
        return
    end
    local entry = entries[frame]
    if not entry then
        entry = { frame = frame }
        entries[frame] = entry
    end
    entry.kind = kind
    ApplyEntry(entry)
end

-- The facade for the rare elements the addon colors itself (selection art).
-- Nil while EUI is missing or skinning is off.
function ns.GetEUISkin()
    return skin
end

-- Run fn on facade arrival and whenever the user's suite-wide looks change
-- (accent color, window styles), so self-drawn art can re-read the accent.
function ns.RegisterEUISkinLooks(fn)
    if type(fn) ~= "function" then
        return
    end
    looksCallbacks[#looksCallbacks + 1] = fn
    if skin and skin.OnLooksChanged then
        skin.OnLooksChanged(fn)
    end
end

if EUI and type(EUI.RegisterSkin) == "function" then
    EUI.RegisterSkin(ADDON_NAME, function(S)
        skin = S
        for _, entry in pairs(entries) do
            ApplyEntry(entry)
        end
        for index = 1, #looksCallbacks do
            if S.OnLooksChanged then
                S.OnLooksChanged(looksCallbacks[index])
            end
        end
    end)
end
