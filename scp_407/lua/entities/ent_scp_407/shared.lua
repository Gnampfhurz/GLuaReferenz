ENT.Base = "base_anim"
ENT.Type = "anim"
ENT.PrintName = "SCP-407"
ENT.Author = "Paid for Modern Gaming"
ENT.Category = "SCP"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Model = "models/props/cs_office/radio.mdl"
ENT.MusicFile = "scp/407_loop.mp3"
ENT.Range = 300
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ActiveUserCount")
end