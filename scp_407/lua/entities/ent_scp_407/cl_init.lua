include("shared.lua")
sound.Add({
    name = "",
    channel = CHAN_AUTO,
    volume = 1.0,
    level = 75,
    pitch = {95, 110},
    sound = "scp/407_loop.mp3"
})

debugData = {}

local auraTable = {}
local soundMap = {}
local timeMap = {}
local isSoundOn = {}
local usageData = {}

net.Receive("scp407_updateStatus", function()
    local ent = net.ReadEntity()
    if ent and ent:IsValid() then
        usageData[ent] = {
            active = net.ReadInt(8),
            maxUsers = net.ReadInt(8)
        }
    end
end)

net.Receive("scp407_syncTime", function()
    local ent = net.ReadEntity()
    if ent and ent:IsValid() then
        timeMap[ent] = net.ReadFloat()
    end
end)

net.Receive("scp407_playSound", function()
    local ent = net.ReadEntity()
    if not (ent and ent:IsValid()) then return end

    local shouldStart = net.ReadBool()
    local newTime = net.ReadFloat()
    local newVol = net.ReadFloat()

    timeMap[ent] = newTime
    isSoundOn[ent] = shouldStart

    if shouldStart and newVol > 0 then
        if not soundMap[ent] then
            local sound = CreateSound(ent, "scp/407_loop.mp3")
            if sound then
                sound:SetSoundLevel(75)
                soundMap[ent] = sound
            end
        end

        if soundMap[ent] and not soundMap[ent]:IsPlaying() then
            soundMap[ent]:Play()
        end

        local playerPos = LocalPlayer():GetPos()
        local entPos = ent:GetPos()
        local dist = playerPos:Distance(entPos)
        local maxDist = 300
        local adjustedVol = 0

        if dist <= maxDist then
            adjustedVol = math.Clamp(1 - (dist / maxDist), 0, 1) * newVol
        end

        if soundMap[ent] then
            soundMap[ent]:ChangeVolume(adjustedVol)
        end
    elseif soundMap[ent] then
        soundMap[ent]:Stop()
        soundMap[ent] = nil
    end
end)

hook.Add("Think", "SCP407_AdjustVolumeThink", function()
    for ent, snd in pairs(soundMap) do
        if ent and ent:IsValid() and snd and snd:IsPlaying() then
            local pPos = LocalPlayer():GetPos()
            local ePos = ent:GetPos()
            local dist = pPos:Distance(ePos)
            local maxDist = 300
            local volume = 0

            if dist <= maxDist then
                volume = math.Clamp(1 - (dist / maxDist), 0, 1)
            end

            snd:ChangeVolume(volume)
        end
    end
end)

net.Receive("scp407_updateTime", function()
    local ply = net.ReadEntity()
    local time = net.ReadFloat()
    local canHear = net.ReadBool()

    if ply:IsPlayer() then
        ply.CanHear407 = canHear
        if canHear and time >= 60 then
            auraTable[ply] = time
        end
    end
end)

net.Receive("scp407_resetEffects", function()
    local who = net.ReadEntity()
    auraTable[who] = nil
end)

net.Receive("scp407_changeModel", function()

end)

hook.Add("RenderScreenspaceEffects", "SCP407_ShowAuraEffect", function()
    local duration = auraTable[LocalPlayer()]
    if not duration then return end

    local strength = math.min((duration - 60) / 240, 0.3)

    if not LocalPlayer().CanHear407 then
        strength = strength * 0.8
    end

    DrawColorModify({
        ["$pp_colour_addg"] = strength * 0.15,
        ["$pp_colour_contrast"] = 1 + strength * 0.1,
        ["$pp_colour_colour"] = 1 - strength * 0.15,
        ["$pp_colour_mulg"] = strength * 0.6
    })

    if duration > 120 then
        DrawMotionBlur(0.2, math.min((duration - 120) / 180, 0.8), 0.01)
    end

    if duration > 180 then
        DrawBloom(0.3, strength * 1.5, 8, 8, 2, 1, 0, 1, 0)
    end
end)

hook.Add("PlayerSpawn", "SCP407_ClearAuraOnSpawn", function(ply)
    auraTable[ply] = nil
end)

hook.Add("PlayerDeath", "SCP407_ClearAuraOnDeath", function(ply)
    auraTable[ply] = nil
end)

function ENT:Draw()
    self:DrawModel()

    if LocalPlayer():GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end

    local pos = self:GetPos() + Vector(0, 0, 25)
    local ang = LocalPlayer():EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)

    local state = usageData[self] or { active = 0, maxUsers = 0 }
    local text, clr = "Verfügbar", Color(68, 255, 68)

    if state.active >= state.maxUsers then
        text, clr = "Spielt Musik (" .. state.active .. "/" .. state.maxUsers .. ")", Color(255, 0, 0)
    elseif state.active == 2 then 
        text, clr = "Nutzbar (" .. state.active .. "/" .. state.maxUsers .. ")", Color(255, 162, 0)
    elseif state.active == 1 then
        text, clr = "Nutzbar (" .. state.active .. "/" .. state.maxUsers .. ")", Color(0, 223, 0)
    end

    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleText("SCP-407", "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText(text, "DermaDefault", 0, 24, clr, TEXT_ALIGN_CENTER)
        draw.SimpleText("E gedrückt halten zum Start/Stop", "DermaDefault", 0, 42, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("SHIFT + E zum Tragen", "DermaDefault", 0, 60, color_white, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

function ENT:OnRemove()
    if soundMap[self] then
        soundMap[self]:Stop()
    end
    soundMap[self] = nil
    isSoundOn[self] = nil
    timeMap[self] = nil
    usageData[self] = nil
end

hook.Add("ShutDown", "SCP407_Cleanup", function()
    for _, s in pairs(soundMap) do
        if s then s:Stop() end
    end

    soundMap = {}
    isSoundOn = {}
    timeMap = {}
    usageData = {}
end)