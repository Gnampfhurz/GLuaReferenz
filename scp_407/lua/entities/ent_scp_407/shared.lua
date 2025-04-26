ENT.Base = "base_gmodentity"
ENT.Type = "anim"
ENT.PrintName = "SCP-407"
ENT.Author = "Paid for Modern Gaming"
ENT.Category = "SCP"
ENT.Spawnable = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ActiveUserCount")
end