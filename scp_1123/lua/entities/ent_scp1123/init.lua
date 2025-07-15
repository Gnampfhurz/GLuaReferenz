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

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:Use(ply)
    if !IsValid(ply) or !ply:IsPlayer() then return end

    if ply:KeyDown(IN_SPEED) and !self:IsPlayerHolding() then
        ply:PickupObject(self)
        self.CarrierSteamID = ply:SteamID()
        self.CarrierPlayer = ply
        return
    end

    if !ply:KeyDown(IN_SPEED) and self:IsCarriedBy(ply) then
        self:RemoveCarrier()
        return
    end

    if !self:HasCarrier() then
        self.InputBuffer[ply] = CurTime()
    end
end

function ENT:Think() 
    local hasCarrier = self:HasCarrier()

    if hasCarrier then 
        self:ValidateCarrier()
        if !self:IsPlayerHolding() then
            self:RemoveCarrier()
            return
        end

        self:CheckPassiveEffects()
    else
        local now = CurTime()
        local changed = false

        for ply, startTime in pairs(self.InputBuffer) do
            if !IsValid(ply) or !ply:KeyDown(IN_USE) then
                self.InputBuffer[ply] = nil
                changed = true
            elseif now - startTime >= 2 then
                if !self:IsOnCooldown(ply) then
                    self:StartHallucination(ply)
                end
                self.InputBuffer[ply] = nil
                changed = true
            end
        end

        if changed and !next(self.InputBuffer) then 
            self.InputBuffer = {}
        end
    end

    if hasCarrier or next(self.InputBuffer) != nil then
        self:NextThink(CurTime() + 1)
        return true
    end
end

-- Sorry could be one function but I like it this way
function ENT:HasCarrier()
    return self.CarrierSteamID != nil
end

function ENT:IsCarriedBy(ply)
    return self.CarrierSteamID == ply:SteamID()
end

function ENT:GetCarrier()
    return self.CarrierPlayer
end

function ENT:RemoveCarrier()
    self.CarrierSteamID = nil
    self.CarrierPlayer = nil
end


function ENT:ValidateCarrier()
    if !self:HasCarrier() then return end
    local ply = self.CarrierPlayer
    if !IsValid(ply) or !ply:IsPlayer() then
        for player in player.Iterator() do
            if player:SteamID() == self.CarrierSteamID then
                self.CarrierPlayer = player
                break
            end
        end
        ply = self.CarrierPlayer
        if !IsValid(ply) then
            self:RemoveCarrier()
            return
        end
    end

    if !ply:Alive() or ply:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then
        self:RemoveCarrier()
    end
end


function ENT:IsOnCooldown(ply)
    return self.ActiveCooldowns[ply] and self.ActiveCooldowns[ply] > CurTime()
end


function ENT:StartHallucination(ply)
    local duration = math.random(SCP1123_Config.min_duration, SCP1123_Config.max_duration)

    net.Start("SCP1123_StartHallucination")
        net.WriteUInt(duration, 6)
    net.Send(ply)

    timer.Simple(duration, function()
        if !IsValid(ply) or !IsValid(self) then return end
        self:ApplyHallucinationDamage(ply, duration)
    end)

    self.ActiveCooldowns[ply] = CurTime() + SCP1123_Config.cooldown_active
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
            local damageInfo = DamageInfo()
            damageInfo:SetDamage(dmg)
            damageInfo:SetAttacker(game.GetWorld())
            damageInfo:SetDamageType(DMG_GENERIC)
            ply:TakeDamageInfo(damageInfo)
        end
    end)
end


function ENT:CheckPassiveEffects()
    if !self:HasCarrier() then return end

    local carrier = self:GetCarrier()
    if !IsValid(carrier) or !carrier:Alive() then
        self:RemoveCarrier()
        return
    end

    if self.PassiveCooldowns[carrier] and self.PassiveCooldowns[carrier] > CurTime() then
        return
    end

    if math.Rand(0, 1) < SCP1123_Config.carrier_chance then
        self:TriggerPassiveEffect(carrier)
        self.PassiveCooldowns[carrier] = CurTime() + SCP1123_Config.cooldown_passive
    end
end


function ENT:TriggerPassiveEffect(ply)
    local duration = math.random(SCP1123_Config.min_duration, SCP1123_Config.max_duration)

    net.Start("SCP1123_TriggerPassive")
        net.WriteUInt(duration, 6)
    net.Send(ply)

    timer.Simple(duration, function()
        if !IsValid(ply) or !IsValid(self) then return end
        self:ApplyHallucinationDamage(ply, duration)
    end)
end


hook.Add("PlayerDisconnected", "SCP1123_PlayerDisconnect", function(ply) --
    for _, ent in ipairs(ents.FindByClass("scp_1123")) do
        if IsValid(ent) and ent:IsCarriedBy(ply) then
            ent:RemoveCarrier()
        end
    end
end)


hook.Add("OnPlayerChangedTeam", "SCP1123_ResetCooldownsOnJobChange", function(ply, oldTeam, newTeam)
    local sid = ply:SteamID()

    for _, ent in ipairs(ents.FindByClass("scp_1123")) do
        if IsValid(ent) then
            ent.ActiveCooldowns[sid] = nil
            ent.PassiveCooldowns[sid] = nil

            if ent:IsCarriedBy(ply) then
                ent:RemoveCarrier()
            end
        end
    end
end)
