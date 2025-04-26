local models = {
    ["models/player/breen.mdl"] = {"models/player/alyx.mdl", "models/player/Group01/female_02.mdl"},
    ["models/player/alyx.mdl"] = {"models/player/breen.mdl"},
    ["models/player/undead/undead.mdl"] = {"models/player/undead/undead.mdl"}
}

local protected = {
    "models/player/combine_soldier.mdl",
    "models/player/combine_super_soldier.mdl"
}

return models, protected