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

    if !IsValid(ply) or ply:SteamID() ~= self.CarrierSteamID then
        for p in player.Iterator() do
            if p:SteamID() == self.CarrierSteamID then
                self.CarrierPlayer = p
                ply = p
                break
            end
        end
    end

    if IsValid(ply) and ply:Alive() and ply:GetPos():DistToSqr(self:GetPos()) <= self.MAX_CARRY_DISTANCE ^ 2 then
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
    if IsValid(self.CarrierPlayer) then
        self:StopPassiveEffectTimer(self.CarrierPlayer)
    end
    self.CarrierSteamID = nil
    self.CarrierPlayer = nil
end

function ENT:Use(ply)
    if !IsValid(ply) then return end

    local sid = ply:SteamID()
    local eid = self:EntIndex()

    if ply:KeyDown(IN_SPEED) and !self:IsPlayerHolding() then
        ply:PickupObject(self)
        self:SetCarrier(ply)
        self:StartPassiveEffectTimer(ply)
        return
    end

    if !ply:KeyDown(IN_SPEED) and self:IsCarriedBy(ply) then
        self:RemoveCarrier()
        return
    end

    local tname = "scp1123_input_" .. eid .. "_" .. sid
    if !timer.Exists(tname) then
        self:StartInputHoldTimer(ply)
    end
end

function ENT:StartInputHoldTimer(ply)
    local sid = ply:SteamID()
    local eid = self:EntIndex()
    local startTime = CurTime()
    local tname = "scp1123_input_" .. eid .. "_" .. sid

    timer.Create(tname, 0.1, 0, function()
        if !IsValid(ply) or !IsValid(self) then timer.Remove(tname) return end
        if !ply:KeyDown(IN_USE) then timer.Remove(tname) return end

        local now = CurTime()
        if now - startTime >= self.HOLD_TIME_REQUIRED then
            if !self:IsOnCooldown(ply) then
                self:StartHallucination(ply)
            end
            timer.Remove(tname)
        end
    end)
end

function ENT:StartPassiveEffectTimer(ply)
    local sid = ply:SteamID()
    local eid = self:EntIndex()
    local tname = "scp1123_passive_" .. eid .. "_" .. sid

    timer.Create(tname, self.THINK_INTERVAL, 0, function()
        if !IsValid(ply) or !IsValid(self) then timer.Remove(tname) return end
        if !self:IsCarriedBy(ply) then timer.Remove(tname) return end

        if !self:IsOnPassiveCooldown(ply) and math.Rand(0, 1) < SCP1123_Config.carrier_chance then
            self:TriggerPassiveEffect(ply)
        end
    end)
end

function ENT:StopPassiveEffectTimer(ply)
    local tname = "scp1123_passive_" .. self:EntIndex() .. "_" .. ply:SteamID()
    if timer.Exists(tname) then timer.Remove(tname) end
end

function ENT:IsOnCooldown(ply)
    local cd = self.ActiveCooldowns[ply:SteamID()]
    if cd and cd > CurTime() then return true elseif cd then self.ActiveCooldowns[ply:SteamID()] = nil end
    return false
end

function ENT:SetCooldown(ply, seconds)
    self.ActiveCooldowns[ply:SteamID()] = CurTime() + seconds
end

function ENT:IsOnPassiveCooldown(ply)
    local cd = self.PassiveCooldowns[ply:SteamID()]
    if cd and cd > CurTime() then return true elseif cd then self.PassiveCooldowns[ply:SteamID()] = nil end
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

    local tname = "scp1123_timer_active_" .. self:EntIndex() .. "_" .. ply:SteamID()
    timer.Create(tname, duration, 1, function()
        if IsValid(ply) and IsValid(self) then
            self:ApplyHallucinationDamage(ply, duration)
        end
    end)

    self:SetCooldown(ply, SCP1123_Config.cooldown_active)
end

function ENT:TriggerPassiveEffect(ply)
    local duration = math.random(SCP1123_Config.min_duration, SCP1123_Config.max_duration)

    net.Start("SCP1123_TriggerPassive")
        net.WriteUInt(duration, 6)
    net.Send(ply)

    local tname = "scp1123_timer_passive_" .. self:EntIndex() .. "_" .. ply:SteamID()
    timer.Create(tname, duration, 1, function()
        if IsValid(ply) and IsValid(self) then
            self:ApplyHallucinationDamage(ply, duration)
        end
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

function ENT:CleanupPlayer(ply)
    local sid = ply:SteamID()
    local eid = self:EntIndex()

    self.ActiveCooldowns[sid] = nil
    self.PassiveCooldowns[sid] = nil

    self:StopPassiveEffectTimer(ply)

    timer.Remove("scp1123_input_" .. eid .. "_" .. sid)

    timer.Remove("scp1123_timer_active_" .. eid .. "_" .. sid)
    timer.Remove("scp1123_timer_passive_" .. eid .. "_" .. sid)

    if self:IsCarriedBy(ply) then
        self:RemoveCarrier()
    end
end

function ENT:OnRemove()
    for _, ply in ipairs(player.GetAll()) do
        self:CleanupPlayer(ply)
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
