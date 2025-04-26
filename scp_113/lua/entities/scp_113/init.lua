AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

local models, protected = include("model_table.lua")
local timersToEnd = {"TransformationDamage", "StartingBurnDamage", "ModelChange", "StartTransformationDamage", "Drop113"}

util.AddNetworkString("NormalTransformation")
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
    self.spawnPosition = self:GetPos()
    self.originalCollision = self:GetCollisionGroup()
    self.currentUser = nil
end

--Legt beim Spieler ein Feld an, wenn er SCP-113 nutzt
--Wenn das Feld schon existiert, dann zählt die Funktion einfach nur hoch
local function countUses(ply)
    if ply.useCount113 then
        ply.useCount113 = ply.useCount113 + 1
    else
        ply.useCount113 = 1
    end
end

--Legt den Schaden fest, der am Ende der Transformation auftritt
--Der Schaden ist hierbei variabel und wird in ENT:Activate113 festgelegt
function ENT:TransformationDamage(ply, damageTick)
    timer.Create("TransformationDamage" .. ply:SteamID64(), 2, 10, function()
        if not ply:Alive() then
            timer.Remove("TransformationDamage" .. ply:SteamID64())
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
--Legt den Verbrennungseffekt fest, der am Anfang in der Lore auftritt wenn man SCP-113 aufhebt
function ENT:ThisStoneIsOnFire(ply)
    timer.Create("StartingBurnDamage" .. ply:SteamID64(), 0.1, 1, function()
        if not ply:Alive() then
            timer.Remove("StartingBurnDamage" .. ply:SteamID64())
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

--Bricht, wie der Name eigentlich schon sagt, alle (wichtigen) Timer ab
local function abortAllTimer(ply)
    for _, timerToEnd in ipairs(timersToEnd) do
        if timer.Exists(timerToEnd .. ply:SteamID64()) then
            timer.Remove(timerToEnd .. ply:SteamID64())
        end
    end
end

--Diese Funktion tritt auf, wenn ein Charakter aus der aktiven Session ausscheider (Tot, Jobwechsel, Disconnect)
--Hierbei werden die Effekte von SCP-113 beendet, sowie alle Timer abgebrochen und die Anzahl der Nutzungen die der Spieler hat entfernt
local function resetUseCount(ply)
    ply.useCount113 = nil
    net.Start("EndBlurAndShake")
    net.Send(ply)
    abortAllTimer(ply)
end

--Diese Funktion startet sobald der Effekt von SCP-113 ändert oder der Spieler nicht mehr eligable ist
--Hierbei wird einfach das SCP wieder sichtbar gemacht und an bestimmte Positionen teleportiert
--Zudem werden die, für das SCP exklusive, Felder wieder vom Spieler entfernt
local function drop113(ply, death)
    local ent = ply.carries113
    ent:SetNoDraw(false)
    ent:DrawShadow(true)
    ent:SetCollisionGroup(ent.originalCollision)
    ent:SetNotSolid(false)
    if death then
        ent:SetPos(ply:GetPos() + Vector(50,0,50))
    --else
    --    ent:SetPos(ent.spawnPosition)
    end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
    ply.carries113 = nil
    ent.currentUser = nil
end

--Diese Funktion ändert das Model
--Bei jeder gerade Nutzung wird das Model einfach auf das originale Model geändert, ansonsten wird aus einer zufälligen Auswahl an festgelegen Models eines genommen
--Die möglichen Models finden sich in model_table.lua unter "models"
local function modelChange(ply)
    local originalModel113 = ply.originalModel113
    if ply:GetModel() == originalModel113 then
        for k,v in pairs(models) do
            if k == originalModel113 then
                local modelAmount = table.Count(v)
                local modelNumber = math.random(1, modelAmount)
                local newModel = v[modelNumber]
                ply:SetModel(newModel)
                return
            end
        end
    else
        ply:SetModel(originalModel113)
        return
    end
end

--Dieser Effekt tritt ein, nachdem jemand zum Zombie wurde und hört erst mit dem Tod der Person auf
--Hierdurch wird signalisiert, dass der Körper sich im Verfallsprozess befindet
function ENT:StartDying(ply)
    local timerName = "PlayerDying"..ply:SteamID64()
    timer.Create(timerName, 1, 0, function()
        if not ply:Alive() or not IsValid(ply) then
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

--Startet den Trageprozess von SCP-131
--Das SCP wird dabei unsichtbar und kollisionslos gemacht, bis der Effekt aufhört
function ENT:StoneIsCarried(ply)
    ply.carries113 = self
    self:SetNoDraw(true)
    self:DrawShadow(false)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:SetNotSolid(true)
    timer.Create("Drop113" .. ply:SteamID64(), 82, 1, function()
        drop113(ply, true)
    end)
end

--This is where the magic happens
--Hier wird die Aktivierung des SCPs gestartet
--Es können ein paar Variablen zur einfach Anpassung angelegt werden
function ENT:Activate113(ply)
    local threshhold = 4                --Dient dazu festzulegen wie oft man das SCP nutzen kann, bevor man zum Zombie wird. Threshhold + 1 ist die Nutzung die den Spieler zum Zombie macht.
    local transformationCD = 60         --Dient dazu festzulegen nach welcher Zeit der Schadenseffekt der Transformation einsetzt und damit die endgültige Transformation beginnt.
    local modelChangeCD = 82            --Dient dazu festzulegen nach welcher Zeit das Model tatsächlich gewechselt wird.
    self.currentUser = ply
    if ply.useCount113 == 1 then
        ply.originalModel113 = ply:GetModel()
    end
    net.Start("NormalTransformation")
    net.Send(ply)
    self:ThisStoneIsOnFire(ply)
    self:StoneIsCarried(ply)
    if ply.useCount113 <= threshhold then
        timer.Create("StartTransformationDamage" .. ply:SteamID64(), transformationCD, 1, function()
            self:TransformationDamage(ply, 1)
        end)
        timer.Create("ModelChange" .. ply:SteamID64(), modelChangeCD, 1, function()
            modelChange(ply)
        end)
    elseif ply.useCount113 == threshhold + 1 then       
        timer.Create("StartTransformationDamage" .. ply:SteamID64(), transformationCD, 1, function()
            self:TransformationDamage(ply, 2)
        end)
        timer.Create("ModelChange" .. ply:SteamID64(), modelChangeCD, 1, function()
            ply:SetModel("models/player/undead/undead.mdl")
            self:StartDying(ply)
        end)
    else
        timer.Create("StartTransformationDamage" .. ply:SteamID64(), transformationCD, 1, function()
            self:TransformationDamage(ply, 10)
        end)
        timer.Create("ModelChange" .. ply:SteamID64(), modelChangeCD, 1, function()
            ply:Kill()
        end)
    end
end

--Prüft ob der Spieler ein Model hat, dass SCP-113 aufheben kann
--Die Liste der Models findet man in model_table.lua als "protected"
local function checkForProtection(ply)
    local playerModel = ply:GetModel()
    for _, v in ipairs(protected) do
        if playerModel == v then
            return true 
        end
    end
    return false 
end

local function isModelValid(ply)
    local playerModel = ply:GetModel()
    for k, _ in pairs(models) do
        if playerModel == k then
            return true
        end
    end
    return false
end

function ENT:Use(ply, caller)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if checkForProtection(ply) then
        if ply:KeyDown(IN_SPEED) then
            ply:PickupObject(self)
        end        
        return
    end
    if not isModelValid(ply) then
        return
    end 
    local cooldown = 90
    self.lastUse = self.lastUse or -cooldown
    if CurTime() < self.lastUse + cooldown then
        return 
    end
    self.lastUse = CurTime()
    countUses(ply)
    self:Activate113(ply)
end

--Kleiner CleanUp sollte das SCP aus irgendeinem Grund entfernt werden
function ENT:OnRemove()
    abortAllTimer()
    if IsValid(self.currentUser) then
        net.Start("EndBlurAndShake")
        net.Send(self.currentUser)
    end
end

--Dieser Hook sorgt dafür, dass SCP-113 wieder sichtbar wird nachdem ein Spieler stirbt während er das SCP trägt (Sandbox)
--Hierbei wird das SCP am Todesort fallen gelassen
hook.Add("PlayerDeath", "ResetCounter", function(ply)
    if ply.useCount113 ~= nil then
        resetUseCount(ply)
    end
    if IsValid(ply.carries113) then
        drop113(ply, true)
    end
end)

--Dieser Hook sorgt dafür, dass SCP-113 wieder sichtbar wird nachdem ein Spieler den Job wechselt während er das SCP trägt (DarkRP)
--Hierbei erscheint das SCP am originalen Spawn des SCPs
hook.Add("OnPlayerChangedTeam", "SwitchJobReset", function(ply)
    if ply.useCount113 ~= nil then
        resetUseCount(ply)
    end
    if IsValid(ply.carries113) then
        drop113(ply, false)
    end
end)

--Dieser Hook sorgt dafür, dass SCP-113 wieder sichtbar wird nachdem ein Spieler disconnected während er das SCP trägt (Sandbox)
--Hierbei erscheint das SCP am originalen Spawn des SCPs
hook.Add("PlayerDisconnected", "DisconnectReset", function(ply)
    if ply.useCount113 ~= nil then
        resetUseCount(ply)
    end
    if IsValid(ply.carries113) then
        drop113(ply, false)
    end
end)