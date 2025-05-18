include("shared.lua")

local blurEndTime = 0

function ENT:Draw()
    self:DrawModel()
    if LocalPlayer():GetPos():DistToSqr(self:GetPos()) > 90000 then return end

    local displayPos = self:GetPos() + Vector(0, 0, 25)
    local displayAng = LocalPlayer():EyeAngles()
    displayAng:RotateAroundAxis(displayAng:Right(), 90)
    displayAng:RotateAroundAxis(displayAng:Up(), -90)

    cam.Start3D2D(displayPos, displayAng, 0.1)
        draw.SimpleText("SCP-113", "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("E zum Benutzen", "DermaDefault", 0, 42, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("SHIFT + E zum Tragen", "DermaDefault", 0, 60, color_white, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

local function TriggerMotionBlur(duration)
	blurEndTime = CurTime() + duration
end

hook.Add("HUDPaint", "UseButtons", function()
	if CurTime() < blurEndTime then
		DrawMotionBlur(0.1, 0.8, 0.01)
	end
end)

net.Receive("Transformation", function()
    local ply = LocalPlayer()
    local timerName = "ScreenShake" .. ply:EntIndex()
	timer.Create(timerName, 1, 81, function()
		util.ScreenShake(ply:GetPos(), 6, 2, 1, 0)
	end)
	TriggerMotionBlur(82)
end)

net.Receive("EndBlurAndShake", function()
	local ply = LocalPlayer()
	TriggerMotionBlur(-1)
	if timer.Exists("ScreenShake" .. ply:EntIndex()) then
		timer.Remove("ScreenShake" .. ply:EntIndex())
	end
end)