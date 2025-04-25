AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Sync
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
        print("SCP-407 Fehler: Phys geht nicht!")
        return
    end

    phys:Wake()

    self.Users = {}
    self.InputBuffer = {}
    self.MaxAllowed = 3 -- Einstellbar wie viele das SCP nutzen koennen
    self.LoopLength = 136 -- Laenge vom Loop-Sound

    self:SetActiveUserCount(0)
    self:SyncStatusToClients()

    -- Checks ob der getestete noch im Bereich von 407 ist
    timer.Create("scp407_thinker_" .. self:EntIndex(), 0.5, 0, function()
        if self:IsValid() then
            self:HandleAuraEffects()
        end
    end)
end

function ENT:SyncStatusToClients()
    net.Start("scp407_updateStatus")
        net.WriteEntity(self)
        net.WriteInt(self:GetActiveUserCount(), 8)
        net.WriteInt(self.MaxAllowed, 8)
    net.Broadcast()
end
-- SHIFT + E zum aufheben wie auf dem RP Server (Wahrscheinlich unnoetig weil ihr das E einfach mit Shift + E gewechselt hattet nh)
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
            if self:IsUserActive(ply) then
                self:DeactivateUser(ply)
            else
                self:ActivateUser(ply)
            end
            self.InputBuffer = {}
        end
    end

    self:NextThink(CurTime() + 0.1)
    return true
end

function ENT:IsUserActive(ply)
    return self.Users[ply] ~= nil
end

function ENT:ActivateUser(ply)
    if self:GetActiveUserCount() >= self.MaxAllowed and not self:IsUserActive(ply) then
        ply:ChatPrint("SCP-407 ist voll belagert! Warte bis einer Platz macht.") -- Anpassbar xD VOLL BELAGERT!!
        return
    end

    local now = CurTime()
    if ply.SCP407LastTime and ply.SCP407LastTime > 0 then
        now = CurTime() - ply.SCP407LastTime
    end

    self.Users[ply] = {
        baseTime = now,
        modelBefore = ply:GetModel()
    }

    ply.SCP407Time = 0
    ply.SCP407OriginalModel = ply:GetModel()

    self:SetActiveUserCount(self:GetActiveUserCount() + 1)
    self:SyncStatusToClients()

    net.Start("scp407_playSound")
        net.WriteEntity(self)
        net.WriteBool(true)
        net.WriteFloat(0)
        net.WriteFloat(1.0)
    net.Send(ply)
end

function ENT:DeactivateUser(ply, keep)
    net.Start("scp407_playSound")
        net.WriteEntity(self)
        net.WriteBool(false)
        net.WriteFloat(0)
        net.WriteFloat(0)
    net.Send(ply)

    if not keep then
        net.Start("scp407_resetEffects")
            net.WriteEntity(ply)
        net.Broadcast()
        ply.SCP407LastTime = 0
    else
        ply.SCP407LastTime = ply.SCP407Time or 0
    end

    self.Users[ply] = nil
    self:SetActiveUserCount(self:GetActiveUserCount() - 1)
    self:SyncStatusToClients()
end

function ENT:RemoveAllUsers()
    for ply in pairs(self.Users) do
        self:DeactivateUser(ply)
    end
end

function ENT:HandleAuraEffects()
    for ply, data in pairs(self.Users) do
        if not ply:Alive() then
            self:DeactivateUser(ply)
            continue
        end

        local dist = ply:GetPos():Distance(self:GetPos())
        local inRange = dist <= (self.Range or 512) -- 512 ist der fallback fallback falls die Distance nicht gesetzt ist/wird

        if not inRange then
            data.outOfRangeTime = data.outOfRangeTime or CurTime()

            if CurTime() - data.outOfRangeTime > 30 then -- Nach 30 Sek soll das SCp von selber fuer ihn ausgehen um ress zu sparen
                self:DeactivateUser(ply, true)
                ply:ChatPrint("SCP-407 wirkt jetzt nicht mehr weiter auf dich. Du bist zu weit weg")
                continue
            end

            net.Start("scp407_updateTime")
                net.WriteEntity(ply)
                net.WriteFloat(ply.SCP407Time or 0)
                net.WriteBool(false)
            net.Send(ply)
            continue
        else
            data.outOfRangeTime = nil
        end

        local elapsed = CurTime() - data.baseTime
        ply.SCP407Time = elapsed

        net.Start("scp407_updateTime")
            net.WriteEntity(ply)
            net.WriteFloat(elapsed)
            net.WriteBool(true)
        net.Send(ply)

        if elapsed >= 180 and not ply.SCP407ModelChanged then
            ply.SCP407ModelChanged = true
            ply:SetModel("models/player/zombie_classic.mdl")
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
                        if tree:IsValid() then tree:Remove() end
                    end)
                end)
            end
            ply.SCP407Killed = true
            self:DeactivateUser(ply)
        end
    end
end

function ENT:OnRemove()
    self:RemoveAllUsers()
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
        if ent:IsValid() then
            ent:DeactivateUser(ply)
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
        if ent:IsValid() then
            ent:DeactivateUser(ply)
        end
    end
end)
