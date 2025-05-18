AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

util.AddNetworkString("Transformation")
util.AddNetworkString("EndBlurAndShake")

function ENT:Initialize()
    self:SetModel("models/props_junk/watermelon01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if phys:IsValid() then
        phys:Wake()
    end
    self.originalCollision = self:GetCollisionGroup()
    self.currentUser = nil
    self.useCooldown = 90
    self.lastUse = -self.useCooldown
    self.transformationCD = 60
    self.modelChangeCD = 82
    self.transformationThreshhold = 4
    self.viableModels = {
        ["models/player/breen.mdl"] = {"models/player/alyx.mdl", "models/player/Group01/female_02.mdl"},
        ["models/player/alyx.mdl"] = {"models/player/breen.mdl"},
        ["models/player/undead/undead.mdl"] = {"models/player/undead/undead.mdl"}
    }
    self.protectedModels = {
        "models/player/combine_soldier.mdl",
        "models/player/combine_super_soldier.mdl"
    }
    self.blacklistedTeams = {
        "Mayor",
        "Job2"
    }
    self.timers = {
        "TransformationDamage",
        "StartingBurnDamage",
        "PlayerDying",
        "Drop113",
        "StartTransformationDamage",
        "ModelChange"
    }
end

--Damage depends on number of uses
function ENT:TransformationDamage(ply, damageTick)
    local timerName = "TransformationDamage" .. ply:EntIndex()
    timer.Create(timerName, 2, 10, function()
        if !IsValid(ply) or !ply:Alive() then
            timer.Remove(timerName)
            return
        end
        local dmg = DamageInfo()
        dmg:SetDamage(damageTick)
        dmg:SetDamageType(DMG_SLASH)
        dmg:SetAttacker(self)
        dmg:SetInflictor(self)
        ply:TakeDamageInfo(dmg)
    end)
end

--This Girl is on Fire
function ENT:ThisStoneIsOnFire(ply)
    local timerName = "StartingBurnDamage" .. ply:EntIndex()
    timer.Create(timerName, 0.1, 1, function()
        if !IsValid(ply) or !ply:Alive() then
            timer.Remove(timerName)
            return
        end
        local dmg = DamageInfo()
        dmg:SetDamage(2)
        dmg:SetDamageType(DMG_BURN)
        dmg:SetAttacker(self)
        dmg:SetInflictor(self)
        ply:TakeDamageInfo(dmg)
    end)
end

--makes the scp "exist" again after use, spawns it on it's old position if non roleplay interactions happen (e.g. jobswitch)
function ENT:DropStone(ply, death)
    self:SetNoDraw(false)
    self:DrawShadow(true)
    self:SetCollisionGroup(self.originalCollision)
    self:SetNotSolid(false)
    if IsValid(ply) then
        ply.carries113 = nil 
        self.currentUser = {}
        if death then
            self:SetPos(ply:GetPos() + Vector(0,0,50))
        end 
    end
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

--tries to kill the player if a threshhold is reached
function ENT:StartKilling(ply)
    local timerName = "PlayerDying" .. ply:EntIndex()
    timer.Create(timerName, 1, 0, function()
        if !IsValid(ply) or !ply:Alive() then
            timer.Remove(timerName)
            return
        end
        local dmg = DamageInfo()
        dmg:SetDamage(5)
        dmg:SetDamageType(DMG_SLASH)
        dmg:SetAttacker(self)
        dmg:SetInflictor(self)
        ply:TakeDamageInfo(dmg)
    end)
end

--checks for protective gear
function ENT:CheckForProtection(ply)
    local playerModel = ply:GetModel()
    for _, v in ipairs(self.protectedModels) do
        if playerModel == v then
            return true 
        end
    end
    return false 
end

--checks for jobs that aren't allowed to interact
function ENT:CheckForBlacklist(ply)
    local plyJob = ply:getJobTable().name
    for _, v in ipairs(self.blacklistedTeams) do
        if plyJob == v then
            return true 
        end
    end
    return false 
end

function ENT:CalculateUses(ply)
    if ply.useCount113 != nil then
        ply.useCount113 = ply.useCount113 + 1
    else
        ply.useCount113 = 1
        ply.originalModel113 = ply:GetModel()
    end
end

--changes the model on every uneven use, sets the model to the original on every even use
function ENT:ModelChange(ply)
    local originalModel = ply.originalModel113
    if ply:GetModel() == originalModel then
        for k,v in pairs(self.viableModels) do
            if k == originalModel then
                local modelAmount = table.Count(v)
                local modelNumber = math.random(1, modelAmount)
                local newModel = v[modelNumber]
                ply:SetModel(newModel)
            end
        end
    else
        ply:SetModel(originalModel)
    end
end

--just makes the scp invisible and non interactable, drops the stone at the end of the intended effect
function ENT:StoneIsCarried(ply)
    local timerName = "Drop113" .. ply:EntIndex()
    ply.carries113 = self
    self:SetNoDraw(true)
    self:DrawShadow(false)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:SetNotSolid(true)
    timer.Create(timerName, self.modelChangeCD, 1, function()
        if !IsValid(ply) or !ply:Alive() then   
            timer.Remove(timerName)
            return
        end
        self:DropStone(ply, true)
    end)
end

function ENT:ChooseTransformationDamage(ply)
    if ply.useCount113 == nil then return end
    if ply.useCount113 <= self.transformationThreshhold then
        self:TransformationDamage(ply, 1)
    elseif ply.useCount113 == self.transformationThreshhold + 1 then
        self:TransformationDamage(ply, 2)
    else
        self:TransformationDamage(ply, 10)
    end     
end

function ENT:ChooseTransformationType(ply)
    if ply.useCount113 == nil then return end
    if ply.useCount113 <= self.transformationThreshhold then
        self:ModelChange(ply)
    elseif ply.useCount113 == self.transformationThreshhold + 1 then
        ply:SetModel("models/player/undead/undead.mdl")
        self:StartKilling(ply)
    else
        ply:Kill()
    end     
end

function ENT:Activate113(ply)
    local startTransformationDamage = "StartTransformationDamage" .. ply:EntIndex()
    local startModelChange = "ModelChange" .. ply:EntIndex()
    self.currentUser = ply
    self:CalculateUses(ply)
    net.Start("Transformation")
    net.Send(ply)
    self:ThisStoneIsOnFire(ply)
    self:StoneIsCarried(ply)
    timer.Create(startTransformationDamage, self.transformationCD, 1, function()
        if !IsValid(ply) or !ply:Alive() then
            timer.Remove(startTransformationDamage)
            return
        end
        self:ChooseTransformationDamage(ply)
    end)
    timer.Create(startModelChange, self.modelChangeCD, 1, function()
        if !IsValid(ply) or !ply:Alive() then
            timer.Remove(startModelChange)
            return
        end
        self:ChooseTransformationType(ply)
    end)
end

function ENT:Use(ply, caller)
    if !IsValid(ply) or !ply:IsPlayer() then return end
    if self:CheckForBlacklist(ply) then return end
    if self:CheckForProtection(ply) then
        if ply:KeyDown(IN_SPEED) then
            ply:PickupObject(self)
        else
            return 
        end
    end
    if CurTime() < self.lastUse + self.useCooldown then
        return 
    end
    self.lastUse = CurTime()
    self:Activate113(ply)
end

function ENT:AbortAllTimers(ply)
    if !IsValid(ply) or !ply:IsPlayer() then return end
    local plyIndex = ply:EntIndex()
    for _, timerToEnd in ipairs(self.timers) do
        if timer.Exists(timerToEnd .. plyIndex) then
            timer.Remove(timerToEnd .. plyIndex)
        end
    end
end

function ENT:ResetUseCount(ply)
    if !IsValid(ply) or !ply:IsPlayer() then return end
    ply.useCount113 = nil 
    net.Start("EndBlurAndShake")
    net.Send(ply)
end

function ENT:OnRemove()
    if self.currentUser and IsValid(self.currentUser) then
        self.AbortAllTimers(self.currentUser)
        self.ResetUseCount(self.currentUser)
        net.Start("EndBlurAndShake")
        net.Send(self.currentUser)
        self.currentUser = nil
    end
end

hook.Add("PlayerDeath", "ResetCounter", function(ply)
    if ply.carries113 then
        if ply.useCount113 != nil then
            ply.carries113:ResetUseCount(ply)
        end
        ply.carries113:DropStone(ply, true)
    end
end)

hook.Add("OnPlayerChangedTeam", "SwitchJobReset", function(ply)
    if ply.carries113 then
        if ply.useCount113 != nil then
            ply.carries113:ResetUseCount(ply)
        end
        ply.carries113:DropStone(ply, false)
    end
end)

hook.Add("PlayerDisconnected", "DisconnectReset", function(ply)
    if ply.carries113 then
        if ply.useCount113 != nil then
            ply.carries113:ResetUseCount(ply)
        end
        ply.carries113:DropStone(ply, false)
    end
end)