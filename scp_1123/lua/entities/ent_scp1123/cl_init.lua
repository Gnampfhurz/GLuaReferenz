include("shared.lua")

local hallucinating = false
local hallucinationEnd = 0
local nextPuppetSpawn = 0
local activePuppets = {}
local jumpscareActive = false
local maxPuppets = 10
local whisperChannel = nil
local heartbeatChannel = nil
local hallucinationProgress = 0
local jumpscareMat = Material("scp1123/jumpscare1.png")
local vignetteMat = Material("scp1123/vignette.png")
local jumpscareAlpha = 0

local puppetModels = {
    "models/props_c17/doll01.mdl",
    "models/scp/juggernaut.mdl",
    "models/zoom/atc_light_model.mdl",
    "models/cultist/class_d_9.mdl",
    "models/player/suits/robber_tie.mdl",
    "models/player/undead/undead.mdl",
    "models/breach173.mdl",
    "models/scp/966.mdl",
}

local jumpscareSounds = {
    "materials/scp1123/tot.wav",
    "npc/zombie/zombie_alert2.wav", 
    "npc/zombie/zombie_alert3.wav",
}

net.Receive("SCP1123_StartHallucination", function()
    local duration = net.ReadUInt(6)
    StartSCP1123Hallucination(duration)
end)

net.Receive("SCP1123_TriggerPassive", function()
    local duration = net.ReadUInt(6)
    StartSCP1123Hallucination(duration)
end)

net.Receive("SCP1123_Jumpscare", function()
    local duration = net.ReadUInt(6)
    local willDie = net.ReadBool()

    timer.Simple(0.05, function()
        TriggerJumpscare(duration)
    end)
end)


function StartSCP1123Hallucination(duration)
    hallucinating = true
    hallucinationEnd = CurTime() + duration
    nextPuppetSpawn = CurTime() + math.Rand(2, 4)

    if IsValid(whisperChannel) and whisperChannel:IsPlaying() then whisperChannel:Stop() end
    if IsValid(heartbeatChannel) and heartbeatChannel:IsPlaying() then heartbeatChannel:Stop() end

    local whisperFile = "sound/hallu" .. math.random(1, 2) .. ".wav"
    local heartbeatFile = "sound/heartbeat.wav"

    sound.PlayFile(whisperFile, "noplay", function(channel)
        if IsValid(channel) then
            channel:SetVolume(0.5)
            channel:Play()
            whisperChannel = channel
        end
    end)

    sound.PlayFile(heartbeatFile, "noplay", function(channel)
        if IsValid(channel) then
            channel:SetVolume(0.5)
            channel:Play()
            heartbeatChannel = channel
        end
    end)

    timer.Create("SCP1123_HallucinationLogic", 0.25, 0, function()
        if !hallucinating then timer.Remove("SCP1123_HallucinationLogic") return end

        local ct = CurTime()
        if ct >= hallucinationEnd then
            hallucinating = false
            CleanupSCP1123Hallucination()
            timer.Remove("SCP1123_HallucinationLogic")
            return
        end

        if ct >= nextPuppetSpawn and #activePuppets < maxPuppets then
            SpawnHallucinationPuppet()
            nextPuppetSpawn = ct + math.Rand(2, 4)
        end

        -- Puppet-Rotation
        local ply = LocalPlayer()
        if !IsValid(ply) then return end
        local eyePos = ply:EyePos()

        for _, puppet in ipairs(activePuppets) do
            if IsValid(puppet) then
                local dir = (eyePos - puppet:GetPos()):Angle()
                dir.p = 0
                puppet:SetAngles(dir)
            end
        end
    end)
end


function TriggerJumpscare(duration)
    if jumpscareActive then return end
    jumpscareActive = true

    local ply = LocalPlayer()
    if !IsValid(ply) then return end

    surface.PlaySound(table.Random(jumpscareSounds))
    util.ScreenShake(ply:GetPos(), 12, 30, 0.7, 300)

    jumpscareAlpha = 255

    timer.Create("SCP1123_JumpscareFade", 0.05, 13, function()
        jumpscareAlpha = math.max(0, jumpscareAlpha - 20)
        if jumpscareAlpha <= 0 then
            jumpscareActive = false
            timer.Remove("SCP1123_JumpscareFade")
        end
    end)
end

hook.Add("HUDPaint", "SCP1123_JumpscareImage", function()
    if !jumpscareActive or jumpscareAlpha <= 0 then return end

    surface.SetDrawColor(255, 255, 255, jumpscareAlpha)
    surface.SetMaterial(jumpscareMat)

    local w, h = ScrW(), ScrH()
    local sizeW, sizeH = w * 0.5, h * 0.5
    local posX, posY = (w - sizeW) / 2, (h - sizeH) / 2

    surface.DrawTexturedRect(posX, posY, sizeW, sizeH)
end)

hook.Add("HUDPaint", "SCP1123_Vignette", function()
    if !hallucinating then return end

    surface.SetDrawColor(255, 255, 255, 180)
    surface.SetMaterial(vignetteMat)
    surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
end)


function SpawnHallucinationPuppet()
    local ply = LocalPlayer()
    if !IsValid(ply) then return end

    local eyePos = ply:EyePos()
    local maxAttempts = 10
    local validPos, finalPos = false, nil

    for i = 1, maxAttempts do
        local ang = ply:EyeAngles()
        ang:RotateAroundAxis(ang:Up(), math.Rand(-120, 120))
        ang:RotateAroundAxis(ang:Right(), math.Rand(-30, 30))
        local dir = ang:Forward()
        local dist = math.random(180, 400)
        local pos = eyePos + dir * dist

        local tr = util.TraceLine({
            start = eyePos,
            endpos = pos,
            filter = ply,
            mask = MASK_SOLID_BRUSHONLY
        })

        if tr.Hit then
            pos = tr.HitPos - dir * 20
        end

        local visTr = util.TraceLine({
            start = eyePos,
            endpos = pos,
            filter = ply,
            mask = MASK_SOLID_BRUSHONLY
        })

        if (!visTr.Hit or visTr.Fraction > 0.8) and (pos - eyePos):GetNormalized():Dot(ply:EyeAngles():Forward()) > -0.4 then
            validPos = true
            finalPos = pos
            break
        end
    end

    if !validPos then
        local ang = ply:EyeAngles()
        ang:RotateAroundAxis(ang:Up(), math.Rand(-60, 60))
        finalPos = eyePos + ang:Forward() * 200
    end

    local model = ClientsideModel(table.Random(puppetModels), RENDERGROUP_OPAQUE)
    if !IsValid(model) then return end

    model:SetModelScale(math.Rand(0.8, 1.2), 0)
    model:SetRenderMode(RENDERMODE_TRANSALPHA)
    model:SetColor(Color(255, 255, 255, 0))
    model:SetPos(finalPos)
    model:SetAngles((ply:EyePos() - finalPos):Angle())

    local id = "SCP1123_Puppet_" .. model:EntIndex()
    local alpha = 0
    local fadeIn = 0.8
    local lifetime = math.Rand(1.5, 3.0)

    timer.Create(id .. "_FadeIn", 0.05, fadeIn / 0.05, function()
        if !IsValid(model) then return end
        alpha = math.min(255, alpha + 20)
        model:SetColor(Color(255, 255, 255, alpha))
    end)

    timer.Simple(lifetime - 0.5, function()
        if !IsValid(model) then return end
        local currentAlpha = 255
        timer.Create(id .. "_FadeOut", 0.05, 10, function()
            if !IsValid(model) then return end
            currentAlpha = math.max(0, currentAlpha - 25)
            model:SetColor(Color(255, 255, 255, currentAlpha))
        end)
    end)

    timer.Simple(lifetime, function()
        if IsValid(model) then
            timer.Remove(id .. "_FadeIn")
            timer.Remove(id .. "_FadeOut")
            model:Remove()
        end
    end)

    table.insert(activePuppets, model)
end


function CleanupSCP1123Hallucination()
    for _, puppet in ipairs(activePuppets) do
        if IsValid(puppet) then puppet:Remove() end
    end
    activePuppets = {}

    if IsValid(jumpscareEntity) then
        jumpscareEntity:Remove()
    end
    jumpscareEntity = nil
    jumpscareActive = false

    if IsValid(whisperChannel) and whisperChannel.Stop then whisperChannel:Stop() end
    if IsValid(heartbeatChannel) and heartbeatChannel.Stop then heartbeatChannel:Stop() end

    whisperChannel = nil
    heartbeatChannel = nil
end


hook.Add("RenderScreenspaceEffects", "SCP1123_ScreenEffect", function()
    if hallucinating then
        hallucinationProgress = math.min(1, hallucinationProgress + FrameTime() * 0.4)
    else
        hallucinationProgress = math.max(0, hallucinationProgress - FrameTime() * 0.6)
    end
    if hallucinationProgress <= 0 then return end

    local s = hallucinationProgress
    local intensity = jumpscareActive and 2.0 or 1.0

    DrawColorModify({
        ["$pp_colour_colour"] = Lerp(s, 1, 0),
        ["$pp_colour_contrast"] = 1 + (0.5 * s * intensity),
        ["$pp_colour_brightness"] = -0.15 * s * intensity
    })

    if jumpscareActive then
        DrawMotionBlur(0.4, 0.8, 0.01)
    end
end)

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if ply:GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end

    local tr = util.TraceLine({start = ply:EyePos(), endpos = self:GetPos(), filter = ply})
    if tr.Hit and tr.Entity != self then return end

    local pos = self:GetPos() + Vector(0, 0, 25)
    local ang = ply:EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)

    local floatOffset = math.sin(RealTime() * 2) * 20

    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleText("SCP-1123", "DermaLarge", 0, 0 + floatOffset, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("E gedrückt halten zum Anfassen", "DermaDefault", 0, 42 + floatOffset, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("SHIFT + E zum Tragen", "DermaDefault", 0, 60 + floatOffset, color_white, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end


hook.Add("Think", "SCP1123_PuppetRotation", function()
    local ply = LocalPlayer()
    if !IsValid(ply) then return end

    local eyePos = ply:EyePos()

    for _, puppet in ipairs(activePuppets) do
        if IsValid(puppet) then
            local dir = (eyePos - puppet:GetPos()):Angle()
            dir.p = 0
            puppet:SetAngles(dir)
        end
    end
end)

