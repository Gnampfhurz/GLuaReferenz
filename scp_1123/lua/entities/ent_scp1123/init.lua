AddCSLuaFile()
include("shared.lua")

util.AddNetworkString("SCP1123_StartHallucination")
util.AddNetworkString("SCP1123_TriggerPassive")
util.AddNetworkString("SCP1123_Jumpscare")

function ENT:Initialize()
    self:SetModel("models/props_mvm/mvm_human_skull_collide.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    self.InputBuffer = {}
    self.ActiveCooldowns = {}
    self.PassiveCooldowns = {}

    self.CarrierSteamID = nil
    self.CarrierPlayer = nil

    self.MAX_CARRY_DISTANCE = 200
    self.HOLD_TIME_REQUIRED = 2
    self.THINK_INTERVAL = 0.5

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:IsCarriedBy(ply)
    return IsValid(ply) and self.CarrierSteamID == ply:SteamID()
end

function ENT:GetValidCarrier()
    if !self.CarrierSteamID then return nil end
    local ply = self.CarrierPlayer

    if !IsValid(ply) or ply:SteamID() != self.CarrierSteamID then
        for p in player.Iterator() do
            if p:SteamID() == self.CarrierSteamID then
                self.CarrierPlayer = p
                ply = p
                break
            end
        end
    end

    if IsValid(ply) and ply:Alive() and ply:GetPos():DistToSqr(self:GetPos()) <= self.MAX_CARRY_DISTANCE^2 then
        return ply
    end

    self:RemoveCarrier()
    return nil
end

function ENT:SetCarrier(ply)
    self.CarrierSteamID = ply:SteamID()
    self.CarrierPlayer = ply
end

function ENT:RemoveCarrier()
    self.CarrierSteamID = nil
    self.CarrierPlayer = nil
end

function ENT:Use(ply)
    if !IsValid(ply) then return end

    if ply:KeyDown(IN_SPEED) and !self:IsPlayerHolding() then
        ply:PickupObject(self)
        self:SetCarrier(ply)
        return
    end

    if !ply:KeyDown(IN_SPEED) and self:IsCarriedBy(ply) then
        self:RemoveCarrier()
        return
    end

    if !self.CarrierSteamID then
        self.InputBuffer[ply:SteamID()] = CurTime()
    end
end

function ENT:Think()
    local carrier = self:GetValidCarrier()

    if carrier then
        if !self:IsPlayerHolding() then
            self:RemoveCarrier()
            return
        end

        self:CheckPassiveEffects(carrier)
    else
        self:ProcessInputBuffer()
    end

    if self.CarrierSteamID or next(self.InputBuffer) then
        self:NextThink(CurTime() + self.THINK_INTERVAL)
        return true
    end
end

function ENT:ProcessInputBuffer()
    local now = CurTime()
    for sid, startTime in pairs(self.InputBuffer) do
        local ply = self:GetPlayerBySteamID(sid)
        if !IsValid(ply) or !ply:KeyDown(IN_USE) then
            self.InputBuffer[sid] = nil
        elseif now - startTime >= self.HOLD_TIME_REQUIRED then
            if !self:IsOnCooldown(ply) then
                self:StartHallucination(ply)
            end
            self.InputBuffer[sid] = nil
        end
    end
end

function ENT:GetPlayerBySteamID(sid)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == sid then
            return ply
        end
    end
    return nil
end

function ENT:IsOnCooldown(ply)
    local sid = ply:SteamID()
    local cd = self.ActiveCooldowns[sid]
    if cd and cd > CurTime() then
        return true
    elseif cd then
        self.ActiveCooldowns[sid] = nil
    end
    return false
end

function ENT:SetCooldown(ply, seconds)
    self.ActiveCooldowns[ply:SteamID()] = CurTime() + seconds
end

function ENT:IsOnPassiveCooldown(ply)
    local sid = ply:SteamID()
    local cd = self.PassiveCooldowns[sid]
    if cd and cd > CurTime() then
        return true
    elseif cd then
        self.PassiveCooldowns[sid] = nil
    end
    return false
end

function ENT:SetPassiveCooldown(ply, seconds)
    self.PassiveCooldowns[ply:SteamID()] = CurTime() + seconds
end

function ENT:StartHallucination(ply)
    local duration = math.random(SCP1123_Config.min_duration, SCP1123_Config.max_duration)

    net.Start("SCP1123_StartHallucination")
        net.WriteUInt(duration, 6)
    net.Send(ply)

    local timerName = "scp1123_timer_active_" .. self:EntIndex() .. "_" .. ply:SteamID()
    timer.Create(timerName, duration, 1, function()
        if !IsValid(ply) or !IsValid(self) then return end
        self:ApplyHallucinationDamage(ply, duration)
    end)

    self:SetCooldown(ply, SCP1123_Config.cooldown_active)
end

function ENT:TriggerPassiveEffect(ply)
    local duration = math.random(SCP1123_Config.min_duration, SCP1123_Config.max_duration)

    net.Start("SCP1123_TriggerPassive")
        net.WriteUInt(duration, 6)
    net.Send(ply)

    local timerName = "scp1123_timer_passive_" .. self:EntIndex() .. "_" .. ply:SteamID()
    timer.Create(timerName, duration, 1, function()
        if !IsValid(ply) or !IsValid(self) then return end
        self:ApplyHallucinationDamage(ply, duration)
    end)

    self:SetPassiveCooldown(ply, SCP1123_Config.cooldown_passive)
end

function ENT:ApplyHallucinationDamage(ply, duration)
    if !IsValid(ply) then return end

    local dmg = CalculateSCP1123Damage(duration)
    local deathChance = GetSCP1123DeathChance(duration) * SCP1123_Config.death_multiplier
    local willDie = math.Rand(0, 1) < deathChance

    net.Start("SCP1123_Jumpscare")
        net.WriteUInt(duration, 6)
        net.WriteBool(willDie)
    net.Send(ply)

    timer.Simple(0.1, function()
        if !IsValid(ply) then return end
        if willDie then
            ply:Kill()
            if self:IsCarriedBy(ply) then
                self:RemoveCarrier()
            end
        else
            local info = DamageInfo()
            info:SetDamage(dmg)
            info:SetAttacker(game.GetWorld())
            info:SetDamageType(DMG_GENERIC)
            ply:TakeDamageInfo(info)
        end
    end)
end

function ENT:CheckPassiveEffects(ply)
    if self:IsOnPassiveCooldown(ply) then return end

    if math.Rand(0, 1) < SCP1123_Config.carrier_chance then
        self:TriggerPassiveEffect(ply)
    end
end

function ENT:CleanupPlayer(ply)
    local sid = ply:SteamID()
    self.InputBuffer[sid] = nil
    self.ActiveCooldowns[sid] = nil
    self.PassiveCooldowns[sid] = nil

    if self:IsCarriedBy(ply) then
        self:RemoveCarrier()
    end

    for _, prefix in ipairs({"active", "passive"}) do
        local tname = "scp1123_timer_" .. prefix .. "_" .. self:EntIndex() .. "_" .. sid
        if timer.Exists(tname) then
            timer.Remove(tname)
        end
    end
end

function ENT:OnRemove()
    for sid in pairs(self.ActiveCooldowns) do
        local a = "scp1123_timer_active_" .. self:EntIndex() .. "_" .. sid
        local b = "scp1123_timer_passive_" .. self:EntIndex() .. "_" .. sid
        if timer.Exists(a) then timer.Remove(a) end
        if timer.Exists(b) then timer.Remove(b) end
    end
end


hook.Add("PlayerDisconnected", "SCP1123_Disconnect", function(ply)
    for _, ent in ipairs(ents.FindByClass("scp_1123")) do
        if IsValid(ent) then
            ent:CleanupPlayer(ply)
        end
    end
end)

hook.Add("OnPlayerChangedTeam", "SCP1123_TeamChange", function(ply)
    for _, ent in ipairs(ents.FindByClass("scp_1123")) do
        if IsValid(ent) then
            ent:CleanupPlayer(ply)
        end
    end
end)
