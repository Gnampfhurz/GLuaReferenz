list.Set("SpawnableEntities", "scp_407_ent", {
    PrintName = "SCP-407",
    ClassName = "scp_407_ent",
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
}, "scp_407_ent")