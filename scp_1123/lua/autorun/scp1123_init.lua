if CLIENT then
    language.Add("ent_scp1123", "SCP-1123")
end

list.Set("gmod_spawnmenu_entities", "ent_scp1123", {
    PrintName = "SCP-1123",
    ClassName = "ent_scp1123",
    Category = "SCP Entities",
    AdminOnly = false
})
