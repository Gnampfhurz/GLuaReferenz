AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

if SERVER then
    resource.AddFile("sound/scp/407_loop.mp3") -- Wichtig für Clients sonst kein Sound
end

local netStrings = {
    "scp407_playSound",
    "scp407_updateTime",
    "scp407_resetEffects",
    "scp407_syncTime",
    "scp407_changeModel",
    "scp407_updateStatus"
}

for _, id in ipairs(netStrings) do
    util.AddNetworkString(id)
end

function ENT:Initialize()
    self:SetModel("models/props/cs_office/radio.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetUseType(CONTINUOUS_USE)

    local phys = self:GetPhysicsObject()
    if not phys or not phys:IsValid() then
        print("[SCP-407] Achtung: PhysObj konnte nicht geladen werden!")
        return
    end

    phys:Wake()

    -- Var
    self.BaumifiziertePlayer = {}
    self.InputBuffer = {}
    self.IsActive = false -- Startet deaktiviert
    self.Radius = 300 -- Standartradius
    self.LoopLength = 136 -- Laenge vom Loop in Sekunden
    self.Activator = nil -- Dazu da um zu zeigen wer es aktiviert hat

    self:SetActiveUserCount(0)
    self:SyncStatusToClients()
    self.DebugLastUpdate = 0 -- fue Debug

    -- Hauptdenker
    timer.Create("scp407_thinker_" .. self:EntIndex(), 0.5, 0, function()
        if self:IsValid() then
            self:HandleNearbyPlayers()
            self:HandleAuraEffects()
        end
    end)
end

function ENT:SyncStatusToClients()
    net.Start("scp407_updateStatus")
        net.WriteEntity(self)
        net.WriteInt(self:GetActiveUserCount(), 8) 
        net.WriteInt(1, 8) -- MaxUser ist fix 1, aber bleibt drin
    net.Broadcast()
end

function ENT:Use(ply)
    if ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_USE) and not self:IsPlayerHolding() then
        ply:PickupObject(self)
        return
    end

    if not self.InputBuffer[ply] then
        self.InputBuffer[ply] = CurTime()
    end
end

function ENT:Think()
    for ply, t in pairs(self.InputBuffer) do
        if not ply:KeyDown(IN_USE) then
            self.InputBuffer[ply] = nil
        elseif CurTime() - t >= 2 then
            if self.IsActive then
                self:DeactivateSCP(ply)
            else
                self:ActivateSCP(ply)
            end
            self.InputBuffer = {} -- Reset damit man nicht doppelt ausloest
        end
    end

    self:NextThink(CurTime() + 0.1)
    return true
end

function ENT:IsPlayerInRange(ply)
    return ply:GetPos():DistToSqr(self:GetPos()) <= (self.Radius * self.Radius)
end
function ENT:ActivateSCP(ply)
    if self.IsActive then return end
    
    self.IsActive = true
    self.Activator = ply
    self:SetActiveUserCount(1)
    self:SyncStatusToClients()

    print("[SCP-407] Aktiviert von " .. ply:Nick())

    self:HandleNearbyPlayers()
    self:BroadcastSoundToNearbyPlayers(true)
end

function ENT:DeactivateSCP(ply)
    if not self.IsActive then return end

    self.IsActive = false
    self.Activator = nil
    self:SetActiveUserCount(0)
    self:SyncStatusToClients()

    print("[SCP-407] Deaktiviert von " .. ply:Nick())

    for affectedPly, _ in pairs(self.BaumifiziertePlayer) do
        if IsValid(affectedPly) then
            net.Start("scp407_playSound")
                net.WriteEntity(self)
                net.WriteBool(false)
                net.WriteFloat(0)
                net.WriteFloat(0)
            net.Send(affectedPly)
        end
    end
end

function ENT:HandleNearbyPlayers()
    if not self.IsActive then return end

    local currentTime = CurTime()
    local entPos = self:GetPos()
    local radiusSquared = self.Radius * self.Radius

    -- PVS Check | Ist crazy 
    local playersToCheck = {}
    for _, ply in ipairs(ents.FindInPVS(self)) do
        if ply:IsPlayer() and ply:Alive() then
            table.insert(playersToCheck, ply)
        end
    end

    -- Reichweite Check | Noch crazier
    local preFiltered = {}
    for _, ply in ipairs(playersToCheck) do
        if ply:GetPos():DistToSqr(entPos) <= radiusSquared * 1.2 then
            table.insert(preFiltered, ply)
        end
    end

    for _, ply in ipairs(preFiltered) do
        local inRange = ply:GetPos():DistToSqr(entPos) <= radiusSquared
        if inRange and not self.BaumifiziertePlayer[ply] then
            self:AddPlayerToEffect(ply)
        elseif inRange and self.BaumifiziertePlayer[ply] then
            self.BaumifiziertePlayer[ply].outOfRangeTime = nil
        end
    end

    for ply, data in pairs(self.BaumifiziertePlayer) do
        if not IsValid(ply) or not ply:Alive() then
            self:RemovePlayerFromEffect(ply)
            continue
        end

        local stillInRange = ply:GetPos():DistToSqr(entPos) <= radiusSquared

        if not stillInRange then
            data.outOfRangeTime = data.outOfRangeTime or currentTime

            if currentTime - data.outOfRangeTime > 30 then
                self:RemovePlayerFromEffect(ply)
                ply:ChatPrint("SCP-407 wirkt nicht mehr auf dich. Du bist zu weit weg!")
            end

            net.Start("scp407_updateTime")
                net.WriteEntity(ply)
                net.WriteFloat(data.timeAffected)
                net.WriteBool(false)
            net.Send(ply)
        end
    end

    if self.IsActive then
        self:UpdateSoundForAllPlayers()
    end
end
function ENT:AddPlayerToEffect(ply)
    if self.BaumifiziertePlayer[ply] then return end

    local now = CurTime()
    local startTime = 0

    if ply.SCP407LastTime and ply.SCP407LastTime > 0 then
        startTime = now - ply.SCP407LastTime
    end

    self.BaumifiziertePlayer[ply] = {
        baseTime = now - startTime,
        timeAffected = startTime,
        modelBefore = ply:GetModel(),
        outOfRangeTime = nil
    }

    ply.SCP407Time = startTime
    ply.SCP407OriginalModel = ply:GetModel()

    net.Start("scp407_playSound")
        net.WriteEntity(self)
        net.WriteBool(true)
        net.WriteFloat(0)
        net.WriteFloat(1.0)
    net.Send(ply)

    print("[SCP-407] Spieler " .. ply:Nick() .. " wurde beeinflusst.")
end

function ENT:RemovePlayerFromEffect(ply, keepTime)
    if not self.BaumifiziertePlayer[ply] then return end

    net.Start("scp407_playSound")
        net.WriteEntity(self)
        net.WriteBool(false)
        net.WriteFloat(0)
        net.WriteFloat(0)
    net.Send(ply)

    if not keepTime then
        net.Start("scp407_resetEffects")
            net.WriteEntity(ply)
        net.Broadcast()

        ply.SCP407LastTime = 0
    else
        ply.SCP407LastTime = self.BaumifiziertePlayer[ply].timeAffected or 0
    end

    self.BaumifiziertePlayer[ply] = nil

    print("[SCP-407] Spieler " .. ply:Nick() .. " nicht mehr beeinflusst.")
end

function ENT:UpdateSoundForAllPlayers()
    local entPos = self:GetPos()
    local fadeDistance = self.Radius * 0.8
    local radiusMinusFade = self.Radius - fadeDistance

    local playersToUpdate = {}

    for ply, _ in pairs(self.BaumifiziertePlayer) do
        if not IsValid(ply) then continue end

        local distance = ply:GetPos():Distance(entPos)
        if distance <= self.Radius then
            local volume = 1.0

            if distance > fadeDistance then
                volume = 1.0 - ((distance - fadeDistance) / radiusMinusFade)
            end

            table.insert(playersToUpdate, {
                player = ply,
                volume = math.Clamp(volume, 0, 1)
            })
        end
    end

    local groupSize = 5 -- Maximal 5 gleichzeitig updaten fuer Performance
    for i = 1, #playersToUpdate, groupSize do
        local endIndex = math.min(i + groupSize - 1, #playersToUpdate)

        for j = i, endIndex do
            local data = playersToUpdate[j]

            net.Start("scp407_playSound")
                net.WriteEntity(self)
                net.WriteBool(true)
                net.WriteFloat(0)
                net.WriteFloat(data.volume)
            net.Send(data.player)
        end
    end
end

function ENT:BroadcastSoundToNearbyPlayers(shouldPlay)
    for _, ply in ipairs(player.GetAll()) do
        if self:IsPlayerInRange(ply) then
            net.Start("scp407_playSound")
                net.WriteEntity(self)
                net.WriteBool(shouldPlay)
                net.WriteFloat(0)
                net.WriteFloat(shouldPlay and 1.0 or 0)
            net.Send(ply)
        end
    end
end
function ENT:HandleAuraEffects()
    if not self.IsActive then return end

    for ply, data in pairs(self.BaumifiziertePlayer) do
        if not ply:Alive() then
            self:RemovePlayerFromEffect(ply)
            continue
        end

        local inRange = self:IsPlayerInRange(ply)

        if not inRange then
            continue
        end

        local now = CurTime()
        local elapsed = now - data.baseTime
        data.timeAffected = elapsed
        ply.SCP407Time = elapsed

        net.Start("scp407_updateTime")
            net.WriteEntity(ply)
            net.WriteFloat(elapsed)
            net.WriteBool(true)
        net.Send(ply)

        if elapsed >= 180 and not ply.SCP407ModelChanged then
            ply:SetModel("models/player/zombie_classic.mdl")
            ply.SCP407ModelChanged = true

            net.Start("scp407_changeModel")
                net.WriteEntity(ply)
                net.WriteBool(true)
            net.Broadcast()
        end

        if elapsed < 60 then
            ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + 1))
        elseif elapsed >= 180 and elapsed < 300 then
            ply:TakeDamage(0.4, self, self)
        elseif elapsed >= 300 and not ply.SCP407Killed then
            if not ply:HasGodMode() then
                local pos = ply:GetPos()
                ply:Kill()

                timer.Simple(0.1, function()
                    local tree = ents.Create("prop_physics")
                    tree:SetModel("models/props/eryk/farmingmod/crop_03.mdl")
                    tree:SetPos(pos)
                    tree:SetAngles(Angle(0, math.random(0, 360), 0))
                    tree:Spawn()

                    if tree:GetPhysicsObject():IsValid() then
                        tree:GetPhysicsObject():EnableMotion(false)
                    end

                    timer.Simple(180, function()
                        if tree:IsValid() then
                            tree:Remove()
                        end
                    end)
                end)
            end
            ply.SCP407Killed = true
            self:RemovePlayerFromEffect(ply)
        end
    end
end

function ENT:OnRemove()
    if self.IsActive then
        for ply, _ in pairs(self.BaumifiziertePlayer) do
            self:RemovePlayerFromEffect(ply)
        end
    end

    self.BaumifiziertePlayer = {}
    timer.Remove("scp407_thinker_" .. self:EntIndex())
end

hook.Add("PlayerDeath", "SCP407_ResetOnDeath", function(ply)
    net.Start("scp407_resetEffects")
        net.WriteEntity(ply)
    net.Broadcast()

    if ply.SCP407OriginalModel then
        ply:SetModel(ply.SCP407OriginalModel)
    end

    ply.SCP407Time = 0
    ply.SCP407LastTime = 0
    ply.SCP407Killed = nil
    ply.SCP407ModelChanged = nil

    for _, ent in ipairs(ents.FindByClass("ent_scp_407")) do
        if ent:IsValid() and ent.BaumifiziertePlayer and ent.BaumifiziertePlayer[ply] then
            ent:RemovePlayerFromEffect(ply)
        end
    end
end)

hook.Add("PlayerSpawn", "SCP407_ResetOnSpawn", function(ply)
    net.Start("scp407_resetEffects")
        net.WriteEntity(ply)
    net.Broadcast()

    if ply.SCP407OriginalModel then
        ply:SetModel(ply.SCP407OriginalModel)
    end

    ply.SCP407Time = 0
    ply.SCP407LastTime = 0
    ply.SCP407Killed = nil
    ply.SCP407ModelChanged = nil
end)

hook.Add("PlayerDisconnected", "SCP407_CleanupOnDisconnect", function(ply)
    for _, ent in ipairs(ents.FindByClass("ent_scp_407")) do
        if ent:IsValid() and ent.BaumifiziertePlayer and ent.BaumifiziertePlayer[ply] then
            ent:RemovePlayerFromEffect(ply)
        end
    end
end)
