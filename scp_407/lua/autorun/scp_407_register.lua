list.Set("SpawnableEntities", "ent_scp_407", {
    PrintName = "SCP-407",
    ClassName = "ent_scp_407t",
    Category = "SCP",
    Model = "models/props/cs_office/radio.mdl"
})

scripted_ents.Register({
    Type = "anim",
    Base = "base_anim",
    PrintName = "SCP-407",
    Author = "Paid",
    Category = "SCP",
    Spawnable = true,
    AdminSpawnable = true,
    Model = "models/props/cs_office/radio.mdl"
}, "ent_scp_407")