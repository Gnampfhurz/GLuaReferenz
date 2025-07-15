AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "SCP-1123"
ENT.Author = "Paid"
ENT.Category = "SCP"
ENT.Spawnable = true
--ENT.AdminSpawnable = true

SCP1123_Config = {
    min_duration = 10,
    max_duration = 30,
    base_damage = 0.8,
    death_multiplier = 1.0,
    cooldown_active = 45,
    cooldown_passive = 120,
    carrier_chance = 0.001,
}

function CalculateSCP1123Damage(duration)
    duration = math.Clamp(duration, 1, SCP1123_Config.max_duration)
    local base = SCP1123_Config.base_damage
    local multiplier = 1 + math.pow(duration / 15, 1.5)
    return math.floor(base * duration * multiplier)
end


function GetSCP1123DeathChance(duration)
    duration = math.Clamp(duration, 0, SCP1123_Config.max_duration)

    if duration <= 10 then
        return 0.02
    elseif duration <= 15 then
        return 0.08
    elseif duration <= 20 then
        return 0.25
    elseif duration <= 25 then
        return 0.60
    else
        return 0.99
    end
end
