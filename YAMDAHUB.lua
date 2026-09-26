# YAMADAHUBNORA
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local hui = (gethui and gethui()) or CoreGui
local Camera = Workspace.CurrentCamera

--------------------------------------------------
-- 0. スキン初期化（軽量化のためアクセサリーや服を削除）
--------------------------------------------------
local function removeSkinAndAccessories(character)
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Accessory") or item:IsA("Clothing") or item:IsA("ShirtGraphic") or item:IsA("CharacterMesh") then
			item:Destroy()
		elseif item:IsA("Folder") and (item.Name == "Accessories" or item.Name == "Outfits") then
			item:Destroy()
		end
	end
	
	-- 顔パーツをリセット
	local head = character:FindFirstChild("Head")
	if head then
		for _, face in ipairs(head:GetChildren()) do
			if face:IsA("Decal") or face:IsA("SpecialMesh") then
				face:Destroy()
			end
		end
	end
end

--------------------------------------------------
-- 1. スピード調整 ＆ Carrie mode ＆ Jump Power 関連の処理
--------------------------------------------------
local DEFAULT_SPEED = 42 -- Carrieオフ時のスピード (42)
local CARRY_SPEED = 20   -- Carrieモード時のスピード (20)
local currentSpeed = DEFAULT_SPEED

-- ジャンプ力の設定
local NORMAL_JUMP_POWER = 100 -- Normal時のジャンプ力
local CARRY_JUMP_POWER = 75   -- Carrieモード時のジャンプ力
local currentJumpPower = NORMAL_JUMP_POWER

local isCarrieMode = false
local speedButtonRef
local carrieButtonRef

local function setCarrieMode(enabled)
	isCarrieMode = enabled
	if isCarrieMode then
		currentSpeed = CARRY_SPEED
		currentJumpPower = CARRY_JUMP_POWER
		if carrieButtonRef then 
			carrieButtonRef.Text = "Carrie mode: ON"
			carrieButtonRef.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
		end
	else
		currentSpeed = DEFAULT_SPEED
		currentJumpPower = NORMAL_JUMP_POWER
		if carrieButtonRef then 
			carrieButtonRef.Text = "Carrie mode: OFF"
			carrieButtonRef.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end
	end
	if speedButtonRef then
		speedButtonRef.Text = "Speed: " .. tostring(currentSpeed)
	end
end

local function applyJumpPower(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.UseJumpPower = true
	humanoid.JumpPower = currentJumpPower
end

local function doJump()
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid.Jump = true
	end
end

UserInputService.JumpRequest:Connect(function()
	doJump()
end)

--------------------------------------------------
-- 2. Anti-Drop 関連の処理
--------------------------------------------------
local function setupAntiDrop(character)
	local function protectTool(tool)
		if tool:IsA("Tool") then
			tool.CanBeDropped = false
			tool.Unequipped:Connect(function()
				task.defer(function()
					local backpack = player:FindFirstChildOfClass("Backpack")
					if backpack and tool.Parent == Workspace then
						tool.Parent = backpack
					end
				end)
			end)
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			protectTool(item)
		end
		backpack.ChildAdded:Connect(protectTool)
	end

	for _, item in ipairs(character:GetChildren()) do
		protectTool(item)
	end
	character.ChildAdded:Connect(protectTool)
end

local function onCharacterAdded(character)
	-- スキンとアクセサリーを削除して軽量化
	removeSkinAndAccessories(character)

	setCarrieMode(false)

	local rootPart = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator", 5)

	applyJumpPower(character)
	setupAntiDrop(character)

	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	
	humanoid.StateChanged:Connect(function(oldState, newState)
		if newState == Enum.HumanoidStateType.FallingDown or newState == Enum.HumanoidStateType.Ragdoll then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)

	local animateScript = character:FindFirstChild("Animate")
	if animateScript then
		animateScript.Enabled = false
	end
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end
	end

	for _, v in ipairs(rootPart:GetChildren()) do
		if v:IsA("BodyVelocity") or v:IsA("BodyPosition") then
			v:Destroy()
		end
	end

	local hbConn
	hbConn = RunService.Heartbeat:Connect(function(dt)
		if not rootPart or not humanoid or humanoid.Health <= 0 then
			if hbConn then hbConn:Disconnect() end
			return
		end
		
		-- 【自動判定】通常スピード（OFF）のときに、他プレイヤーのキャラを掴んで接続された（＝キャリーループ等で重くなった）かを検知
		if not isCarrieMode then
			for _, desc in ipairs(character:GetDescendants()) do
				if desc:IsA("WeldConstraint") or desc:IsA("Weld") then
					local p0, p1 = desc.Part0, desc.Part1
					if (p0 and p0.Parent and Players:GetPlayerFromCharacter(p0.Parent) and Players:GetPlayerFromCharacter(p0.Parent) ~= player) or
					   (p1 and p1.Parent and Players:GetPlayerFromCharacter(p1.Parent) and Players:GetPlayerFromCharacter(p1.Parent) ~= player) then
						setCarrieMode(true)
						break
					end
				end
			end
		end
		
		-- ジャンプ力を随時反映
		humanoid.JumpPower = currentJumpPower
		
		local moveDir = humanoid.MoveDirection
		local currentVelocity = rootPart.AssemblyLinearVelocity
		
		if moveDir.Magnitude > 0 then
			local targetVelocityX = moveDir.X * currentSpeed
			local targetVelocityZ = moveDir.Z * currentSpeed
			rootPart.AssemblyLinearVelocity = Vector3.new(targetVelocityX, currentVelocity.Y, targetVelocityZ)
		else
			rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
		end
	end)
end


--------------------------------------------------
-- 3. Anti-Ragdoll 関連の処理
--------------------------------------------------
local antiRagdollConnection

local function StartAntiRagdoll()
	if antiRagdollConnection then
		antiRagdollConnection:Disconnect()
	end

	antiRagdollConnection = RunService.Heartbeat:Connect(function()
		local char = player.Character
		if not char then return end

		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not hum or not root then return end

		local state = hum:GetState()
		local ragdolled =
			state == Enum.HumanoidStateType.Physics
			or state == Enum.HumanoidStateType.Ragdoll
			or state == Enum.HumanoidStateType.FallingDown

		local endTime = player:GetAttribute("RagdollEndTime")
		if endTime and (endTime - Workspace:GetServerTimeNow()) > 0 then
			ragdolled = true
		end

		if ragdolled then
			pcall(function()
				player:SetAttribute("RagdollEndTime", Workspace:GetServerTimeNow())
			end)

			for _, obj in ipairs(char:GetDescendants()) do
				if obj:IsA("BallSocketConstraint") then
					obj:Destroy()
				elseif obj:IsA("Attachment") and string.find(obj.Name, "RagdollAttachment") then
					obj:Destroy()
				end
			end

			for _, obj in ipairs(char:GetDescendants()) do
				if obj:IsA("Motor6D") and not obj.Enabled then
					obj.Enabled = true
				end
			end

			if hum.Health > 0 then
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end

			Workspace.CurrentCamera.CameraSubject = hum
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

StartAntiRagdoll()

player.CharacterAdded:Connect(function(char)
	task.wait(0.5)
	StartAntiRagdoll()
	onCharacterAdded(char)
end)


--------------------------------------------------
-- 4. X-Ray 関連の処理
--------------------------------------------------
local xrayEnabled = false
local xrayConnection

local function startXRay()
	if xrayConnection then
		xrayConnection:Disconnect()
		xrayConnection = nil
	end
	
	xrayConnection = RunService.Heartbeat:Connect(function()
		local Plots = Workspace:FindFirstChild("Plots")
		if Plots then
			for _, Plot in ipairs(Plots:GetChildren()) do
				if Plot:IsA("Model") and Plot:FindFirstChild("Decorations") then
					for _, Part in ipairs(Plot.Decorations:GetDescendants()) do
						if Part:IsA("BasePart") then
							Part.Transparency = 0.8
						end
					end
				end
			end
		end
	end)
end

local function stopXRay()
	if xrayConnection then
		xrayConnection:Disconnect()
		xrayConnection = nil
	end
	
	local Plots = Workspace:FindFirstChild("Plots")
	if Plots then
		for _, Plot in ipairs(Plots:GetChildren()) do
			if Plot:IsA("Model") and Plot:FindFirstChild("Decorations") then
				for _, Part in ipairs(Plot.Decorations:GetDescendants()) do
					if Part:IsA("BasePart") then
						Part.Transparency = 1
					end
				end
			end
		end
	end
end

local function toggleXRay()
	xrayEnabled = not xrayEnabled
	if xrayEnabled then
		startXRay()
	else
		stopXRay()
	end
end


--------------------------------------------------
-- 5. Auto-Steal 関連の処理
--------------------------------------------------
local STEAL_RADIUS = 60
local STEAL_TIME = 0.3
local FIRE_COOLDOWN = 0.2
local isStealing = false
local lastFire = 0
local progressBarBg, progressFill, percentLabel

local function setupAutoStealUI()
	local sg = player.PlayerGui:FindFirstChild("J hub ")
	if not sg then
		sg = Instance.new("ScreenGui")
		sg.Name = "J hub "
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.Parent = player.PlayerGui
	end
	if progressBarBg then return end

	progressBarBg = Instance.new("Frame")
	progressBarBg.Size = UDim2.new(0, 120, 0, 10)
	progressBarBg.Position = UDim2.new(0.5, -60, 1, -110)
	progressBarBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	progressBarBg.BorderSizePixel = 0
	progressBarBg.Parent = sg
	Instance.new("UICorner", progressBarBg).CornerRadius = UDim.new(0, 5)

	progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBarBg
	Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 5)

	percentLabel = Instance.new("TextLabel")
	percentLabel.Size = UDim2.new(1, 0, 1, 0)
	percentLabel.BackgroundTransparency = 1
	percentLabel.Font = Enum.Font.GothamBold
	percentLabel.TextSize = 8
	percentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	percentLabel.Text = "0%"
	percentLabel.Parent = progressBarBg
end

local function getHRP()
	local c = player.Character
	if not c then return nil end
	return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
end

local function promptPos(p)
	local parent = p.Parent
	if not parent then return nil end
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
		return parent.Parent.Position
	end
	if parent:IsA("Model") then
		local pp = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
		if pp then return pp.Position end
	end
	return nil
end

local function isStealPrompt(p)
	if not p.Enabled then return false end
	local at = (p.ActionText or ""):lower()
	local ot = (p.ObjectText or ""):lower()
	local nm = (p.Name or ""):lower()
	if at:find("steal") or ot:find("steal") or nm:find("steal") then return true end
	if at:find("take") or ot:find("take") then return true end
	if at:find("grab") or ot:find("grab") then return true end
	if at == "" and (nm:find("prompt") or nm:find("grab") or nm:find("take")) then return true end
	return false
end

local function isMyPlot(plot)
	local sign = plot:FindFirstChild("PlotSign")
	if sign then
		local yb = sign:FindFirstChild("YourBase")
		if yb and yb:IsA("BillboardGui") and yb.Enabled then return true end
	end
	local owner = plot:FindFirstChild("Owner")
	if owner and owner:IsA("ObjectValue") and owner.Value == player then return true end
	return false
end

local function findNearestPrompt()
	local hrp = getHRP()
	if not hrp then return nil end
	local myPos = hrp.Position
	local nearest, dist = nil, math.huge

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and isStealPrompt(d) then
			local pos = promptPos(d)
			if pos then
				local ancestor = d
				local skip = false
				while ancestor and ancestor ~= Workspace do
					local par = ancestor.Parent
					if par and par.Name == "Plots" then
						if isMyPlot(ancestor) then skip = true end
						break
					end
					ancestor = par
				end
				if not skip then
					local d2 = (pos - myPos).Magnitude
					if d2 <= STEAL_RADIUS and d2 < dist then
						nearest, dist = d, d2
					end
				end
			end
		end
	end
	return nearest
end

local function updateProgressBar(p)
	if progressFill then progressFill.Size = UDim2.new(p, 0, 1, 0) end
	if percentLabel then percentLabel.Text = math.floor(p * 100) .. "%" end
end

local function tryFire(prompt)
	local hold = math.max(prompt.HoldDuration or 0.1, STEAL_TIME)

	if getconnections then
		local beganConns = getconnections(prompt.PromptButtonHoldBegan)
		local endedConns = getconnections(prompt.PromptButtonHoldEnded)
		local trigConns  = getconnections(prompt.Triggered)

		if #beganConns > 0 then
			for _, c in ipairs(beganConns) do
				if c.Function then pcall(c.Function) end
			end
			task.wait(hold)
			for _, c in ipairs(endedConns) do
				if c.Function then pcall(c.Function) end
			end
			for _, c in ipairs(trigConns) do
				if c.Function then pcall(c.Function) end
			end
			return true
		end
	end

	if typeof(fireproximityprompt) == "function" then
		local ok = pcall(fireproximityprompt, prompt)
		if ok then return true end
	end

	local ok = pcall(function()
		prompt:InputHoldBegin()
		task.wait(hold)
		prompt:InputHoldEnd()
	end)
	return ok
end

local function executeSteal(prompt)
	if isStealing or not prompt then return end
	if tick() - lastFire < FIRE_COOLDOWN then return end
	lastFire = tick()
	isStealing = true

	task.spawn(function()
		local start = tick()
		while tick() - start < STEAL_TIME do
			local p = math.clamp((tick() - start) / STEAL_TIME, 0, 1)
			updateProgressBar(p)
			task.wait()
		end
		updateProgressBar(1)
		task.wait(0.02)
		updateProgressBar(0)
	end)

	task.spawn(function()
		pcall(tryFire, prompt)
		task.wait(0.1)
		isStealing = false
	end)
end

local stealConn
local function startAutoSteal()
	setupAutoStealUI()
	if stealConn then return end
	stealConn = RunService.Heartbeat:Connect(function()
		local ok, prompt = pcall(findNearestPrompt)
		if ok and prompt then 
			pcall(executeSteal, prompt) 
		end
	end)
end


--------------------------------------------------
-- 6. 次のベース（Next Base）表示機能の処理
--------------------------------------------------
local function initNextBaseTracker()
	if _G.__NextBaseCleanup then pcall(_G.__NextBaseCleanup) end
	local Plots = Workspace:WaitForChild("Plots")
	local BASE_POSITIONS = {
		Vector3.new(-342.439, 10.399, 113.107),
		Vector3.new(-342.439, 10.465,   6.107),
		Vector3.new(-476.752, 10.465, 114.107),
		Vector3.new(-476.752, 10.465,   7.107),
		Vector3.new(-342.440, 10.464, 220.107),
		Vector3.new(-476.752, 10.465, 221.107),
		Vector3.new(-342.439, 10.465,-100.893),
		Vector3.new(-476.752, 10.465, -99.893),
	}
	local MATCH_TOL = 6
	local EMPTY_TEXT = "Empty Base"
	local ARROW = utf8.char(0x2B07)
	
	local function baseIndexFor(model)
		local ok, cf = pcall(function() return (model:GetBoundingBox()) end)
		if not ok then return nil end
		local p, bestI, bestD = cf.Position
		for i, bp in ipairs(BASE_POSITIONS) do
			local dx, dz = p.X - bp.X, p.Z - bp.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if not bestD or d < bestD then bestI, bestD = i, d end
		end
		return (bestD and bestD <= MATCH_TOL) and bestI or nil
	end

	local bases = {}
	local connected = {}
	local conns = {}

	local anchor = Instance.new("Part")
	anchor.Name = "__NextBaseAnchor"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = CoreGui

	local bb = Instance.new("BillboardGui")
	bb.Name = "NextBaseBillboard"
	bb.Adornee = anchor
	bb.Size = UDim2.fromScale(32, 13)
	bb.StudsOffset = Vector3.new(0, 10, 0)
	bb.MaxDistance = math.huge
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = anchor

	local panel = Instance.new("Frame", bb)
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.ZIndex = 0
	local panelCorner = Instance.new("UICorner", panel)
	panelCorner.CornerRadius = UDim.new(0, 12)

	local top = Instance.new("TextLabel", bb)
	top.BackgroundTransparency = 1
	top.AnchorPoint = Vector2.new(0.5, 0.5)
	top.Position = UDim2.fromScale(0.5, 0.30)
	top.Size = UDim2.fromScale(0.95, 0.50)
	top.Font = Enum.Font.GothamBlack
	top.Text = ARROW .. "  次のベース  " .. ARROW
	top.TextScaled = true
	top.TextColor3 = Color3.fromRGB(255, 255, 255)
	top.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	top.TextStrokeTransparency = 0
	top.ZIndex = 1

	local bottom = Instance.new("TextLabel", bb)
	bottom.BackgroundTransparency = 1
	bottom.AnchorPoint = Vector2.new(0.5, 0.5)
	bottom.Position = UDim2.fromScale(0.5, 0.72)
	bottom.Size = UDim2.fromScale(0.95, 0.42)
	bottom.Font = Enum.Font.GothamBlack
	bottom.Text = "空きベース"
	bottom.TextScaled = true
	bottom.TextColor3 = Color3.fromRGB(255, 255, 255)
	bottom.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	bottom.TextStrokeTransparency = 0
	bottom.ZIndex = 1

	local function isEmpty(label)
		return (label.Text:gsub("^%s+", ""):gsub("%s+$", "")) == EMPTY_TEXT
	end

	local function recompute()
		local targetIdx
		for i = 1, #BASE_POSITIONS do
			local b = bases[i]
			if b and b.label and isEmpty(b.label) then targetIdx = i break end
		end
		if targetIdx then
			anchor.CFrame = bases[targetIdx].cf
			bb.Enabled = true
		else
			bb.Enabled = false
		end
	end

	local function connectLabel(label)
		if connected[label] then return end
		connected[label] = true
		table.insert(conns, label:GetPropertyChangedSignal("Text"):Connect(recompute))
	end

	local function scan()
		for _, plot in ipairs(Plots:GetChildren()) do
			local sign  = plot:FindFirstChild("PlotSign")
			local model = sign and sign:FindFirstChild("Model")
			local gui   = sign and sign:FindFirstChild("SurfaceGui")
			local fr    = gui and gui:FindFirstChild("Frame")
			local label = fr and fr:FindFirstChild("TextLabel")
			if model and label then
				local idx = baseIndexFor(model)
				if idx then
					bases[idx] = { label = label, cf = (select(1, model:GetBoundingBox())) }
					connectLabel(label)
				end
			end
		end
		recompute()
	end

	scan()
	table.insert(conns, Plots.DescendantAdded:Connect(function(d)
		if d:IsA("TextLabel") then task.defer(scan) end
	end))
	table.insert(conns, Plots.ChildAdded:Connect(function() task.defer(scan) end))

	_G.__NextBaseCleanup = function()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		if anchor then anchor:Destroy() end
		_G.__NextBaseCleanup = nil
	end
end


--------------------------------------------------
-- 7. Podium ESP 機能の処理
--------------------------------------------------
local function initPodiumESP()
	if _G.__PodiumESPCleanup then pcall(_G.__PodiumESPCleanup) end

	local Plots = Workspace:WaitForChild("Plots")
	local PALETTE = {
		WHITE  = Color3.fromRGB(255, 255, 255),
		BLACK  = Color3.fromRGB(0, 0, 0),
	}

	local function isDay()
		local t = Lighting.ClockTime
		return t >= 6 and t < 18
	end
	local function themeColor()
		return isDay() and PALETTE.BLACK or PALETTE.WHITE
	end
	local function themeOutline()
		return isDay() and PALETTE.WHITE or PALETTE.BLACK
	end

	local CFG = {
		COLLIDE       = true,
		SHOW_NUMBERS  = true,
	}

	local FILL_T, INNER_T, THICK = 0.55, 0.42, 0.05
	local PULSE_SPEED, PULSE_AMOUNT = 2, 0.12

	local TEMPLATE = {
		{ 18.500,  1.531, -14.476,  90}, { 18.500,  1.531,  -6.976,  90}, { 18.500,  1.531,   0.524,  90},
		{ 18.500,  1.531,   8.024,  90}, { 18.500,  1.531,  15.524,  90},
		{-18.536,  1.531,  15.524, -90}, {-18.536,  1.531,   8.024, -90}, {-18.536,  1.531,   0.524, -90},
		{-18.536,  1.531,  -6.976, -90}, {-18.536,  1.531, -14.476, -90},
		{ 18.500, 19.531, -14.476,  90}, { 18.500, 19.531,  -6.976,  90}, { 18.500, 19.531,   0.524,  90},
		{ 18.500, 19.531,   8.024,  90}, { 18.500, 19.531,  15.524,  90},
		{-18.380, 19.531, -14.452, -90}, {-18.380, 19.531,  -6.952, -90}, {-18.380, 19.531,   0.548, -90},
		{ 18.500, 36.531, -12.476,  90}, { 18.500, 36.531,  -4.976,  90}, { 18.500, 36.531,   2.524,  90},
		{ 18.500, 36.531,  10.024,  90}, { 18.500, 36.531,  17.524,  90},
		{-18.472, 36.531, -12.501, -90}, {-18.471, 36.531,  -5.001, -90}, {-18.471, 36.531,   2.499, -90},
		{-18.471, 36.531,   9.999, -90}, {-18.471, 36.531,  17.499, -90},
	}

	local OUTER, INNER_SZ, INNER_UP = Vector3.new(6, 0.25, 6), Vector3.new(4, 0.25, 4), 0.25

	local _rng = Random.new(os.clock() * 1e6)
	local _NAME_POOL = { "Part", "Mesh", "MeshPart", "Union", "Wedge", "Cylinder", "Model", "Frame", "Handle", "Body", "Root" }
	local function _fakeName()
		return _NAME_POOL[_rng:NextInteger(1, #_NAME_POOL)]
	end

	for _, where in ipairs({Workspace, CoreGui, hui, Camera}) do
		for _, n in ipairs({"__PodiumMarkers", "__PodiumTest", "__PodiumCollide"}) do
			local o = where:FindFirstChild(n)
			if o then pcall(function() o:Destroy() end) end
		end
	end

	local markers, fills, podiumConns = {}, {}, {}
	local collideParts, labelAnchors = {}, {}
	local labelData = {}
	local labelsByPlot = {}
	local currentPlotEsp = nil
	local alive = true

	local function keep(x) markers[#markers + 1] = x x.Parent = hui return x end

	local function clearPodium()
		for _, m in ipairs(markers) do pcall(function() m:Destroy() end) end
		table.clear(markers)
		table.clear(fills)
		for _, p in ipairs(collideParts) do pcall(function() p:Destroy() end) end
		table.clear(collideParts)
		for _, p in ipairs(labelAnchors) do pcall(function() p:Destroy() end) end
		table.clear(labelAnchors)
		table.clear(labelsByPlot)
		table.clear(labelData)
		currentPlotEsp = nil
	end

	local function box(adornee, cf, size, color, trans, isFill)
		local a = Instance.new("BoxHandleAdornment")
		a.Adornee = adornee
		a.Size = size
		a.CFrame = cf
		a.Color3 = color
		a.Transparency = trans
		a.AlwaysOnTop = false
		a.ZIndex = 0
		keep(a)
		if isFill then fills[#fills + 1] = { a = a, base = trans } end
		return a
	end

	local function edges(root, cf, size, color)
		local t = THICK * 1.6
		local hx, hz, y = size.X * 0.5, size.Z * 0.5, size.Y * 0.5
		box(root, cf * CFrame.new(0, y,  hz), Vector3.new(size.X, t, t), color, 0)
		box(root, cf * CFrame.new(0, y, -hz), Vector3.new(size.X, t, t), color, 0)
		box(root, cf * CFrame.new( hx, y, 0), Vector3.new(t, t, size.Z), color, 0)
		box(root, cf * CFrame.new(-hx, y, 0), Vector3.new(t, t, size.Z), color, 0)
	end

	local function solid(worldCF)
		if not CFG.COLLIDE then return end
		local p = Instance.new("Part")
		p.Name = _fakeName()
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Massless = true
		p.Size = OUTER
		p.CFrame = worldCF
		p.Parent = Camera
		collideParts[#collideParts + 1] = p
	end

	local function makeInvisibleAnchor(worldCF)
		local a = Instance.new("Part")
		a.Name = _fakeName()
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.CanTouch = false
		a.CastShadow = false
		a.Transparency = 1
		a.Size = Vector3.new(0.1, 0.1, 0.1)
		a.CFrame = worldCF
		a.Parent = Camera
		labelAnchors[#labelAnchors + 1] = a
		return a
	end

	local function labelFor(plot, adornee, slotNum)
		if not CFG.SHOW_NUMBERS then return end

		local bg = Instance.new("BillboardGui")
		bg.Adornee = adornee
		bg.Size = UDim2.new(2.2, 20, 1.35, 12)
		bg.StudsOffset = Vector3.new(0, 3.2, 0)
		bg.AlwaysOnTop = true
		bg.LightInfluence = 0
		bg.MaxDistance = 400
		bg.ClipsDescendants = false
		bg.Enabled = false

		local panel = Instance.new("Frame")
		panel.Size = UDim2.new(1, 0, 1, 0)
		panel.BackgroundColor3 = themeColor()
		panel.BackgroundTransparency = 0
		panel.BorderSizePixel = 0
		panel.Parent = bg

		local panelCorner = Instance.new("UICorner")
		panelCorner.CornerRadius = UDim.new(0.3, 0)
		panelCorner.Parent = panel

		local border = Instance.new("Frame")
		border.Size = UDim2.new(1, 0, 1, 0)
		border.BackgroundTransparency = 1
		border.Parent = panel

		local borderCorner = Instance.new("UICorner")
		borderCorner.CornerRadius = UDim.new(0.3, 0)
		borderCorner.Parent = border

		local borderStroke = Instance.new("UIStroke")
		borderStroke.Color = themeOutline()
		borderStroke.Thickness = 1.5
		borderStroke.Transparency = 0
		borderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		borderStroke.Parent = border

		local num = Instance.new("TextLabel")
		num.Size = UDim2.new(1, 0, 1, 0)
		num.BackgroundTransparency = 1
		num.Text = tostring(slotNum)
		num.Font = Enum.Font.GothamBlack
		num.TextScaled = true
		num.TextColor3 = themeOutline()
		num.TextXAlignment = Enum.TextXAlignment.Center
		num.TextYAlignment = Enum.TextYAlignment.Center
		num.Parent = panel

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.1, 0)
		pad.PaddingRight = UDim.new(0.1, 0)
		pad.PaddingTop = UDim.new(0.08, 0)
		pad.PaddingBottom = UDim.new(0.08, 0)
		pad.Parent = num

		local sizeConstraint = Instance.new("UITextSizeConstraint")
		sizeConstraint.MaxTextSize = 500
		sizeConstraint.MinTextSize = 6
		sizeConstraint.Parent = num

		local numStroke = Instance.new("UIStroke")
		numStroke.Color = themeColor()
		numStroke.Thickness = 2
		numStroke.Transparency = 0
		numStroke.LineJoinMode = Enum.LineJoinMode.Round
		numStroke.Parent = num

		keep(bg)
		labelData[bg] = { panel = panel, borderStroke = borderStroke, num = num, numStroke = numStroke }
		if not labelsByPlot[plot] then labelsByPlot[plot] = {} end
		labelsByPlot[plot][#labelsByPlot[plot] + 1] = bg
	end

	local function colorFor(i)
		return themeColor()
	end

	local function drawSlot(plot, root, e, slotNum)
		local color = colorFor(slotNum)
		local cf = CFrame.new(e[1], e[2], e[3]) * CFrame.Angles(0, math.rad(e[4]), 0)
		local worldCF = root.CFrame * cf
		local anchor = makeInvisibleAnchor(worldCF)
		box(anchor, CFrame.new(), OUTER, color, FILL_T, true)
		box(anchor, CFrame.new(0, INNER_UP, 0), INNER_SZ, color, INNER_T, true)
		edges(anchor, CFrame.new(), OUTER, color)
		solid(worldCF)
		labelFor(plot, anchor, slotNum)
	end

	local function buildPodium()
		if not alive then return end
		clearPodium()
		for _, plot in ipairs(Plots:GetChildren()) do
			local root = plot:FindFirstChild("MainRoot")
			if root then
				for i = 1, #TEMPLATE do
					drawSlot(plot, root, TEMPLATE[i], i)
				end
			end
		end
	end

	buildPodium()

	local function findCurrentPlotEsp()
		local char = player.Character
		if not char then return nil end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		local pos = hrp.Position
		local best, bestDist = nil, math.huge
		for _, plot in ipairs(Plots:GetChildren()) do
			local root = plot:FindFirstChild("MainRoot")
			if root then
				local d = (root.Position - pos).Magnitude
				if d < bestDist then
					best = plot
					bestDist = d
				end
			end
		end
		if bestDist > 100 then return nil end
		return best
	end

	local function updateVisibilityEsp()
		local newPlot = findCurrentPlotEsp()
		if newPlot == currentPlotEsp then return end
		currentPlotEsp = newPlot
		for plot, list in pairs(labelsByPlot) do
			local show = (plot == currentPlotEsp)
			for _, bg in ipairs(list) do
				if bg and bg.Parent then bg.Enabled = show end
			end
		end
	end

	local lastThemeDay = nil
	local function applyTheme()
		local day = isDay()
		if day == lastThemeDay then return end
		lastThemeDay = day

		local fillColor = themeColor()
		local outline = themeOutline()

		for _, m in ipairs(markers) do
			if m:IsA("BoxHandleAdornment") then
				m.Color3 = fillColor
			end
		end
		for bg, d in pairs(labelData) do
			if bg.Parent then
				d.panel.BackgroundColor3 = fillColor
				d.borderStroke.Color = outline
				d.num.TextColor3 = outline
				d.numStroke.Color = fillColor
			end
		end
	end

	local pending = false
	local function rebuildPodium()
		if pending or not alive then return end
		pending = true
		task.delay(0.4, function()
			pending = false
			buildPodium()
			updateVisibilityEsp()
		end)
	end

	local function watch(plot)
		if not plot:FindFirstChild("MainRoot") then
			local root = plot:WaitForChild("MainRoot", 30)
			if root and alive then rebuildPodium() end
		end
	end
	for _, plot in ipairs(Plots:GetChildren()) do task.spawn(watch, plot) end
	podiumConns[#podiumConns + 1] = Plots.ChildAdded:Connect(function(plot)
		task.spawn(watch, plot)
		rebuildPodium()
	end)

	podiumConns[#podiumConns + 1] = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = Workspace.CurrentCamera
		if alive then rebuildPodium() end
	end)

	podiumConns[#podiumConns + 1] = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
		applyTheme()
	end)

	do
		local acc = 0
		local visAcc = 0
		podiumConns[#podiumConns + 1] = RunService.Heartbeat:Connect(function(dt)
			acc = acc + dt
			visAcc = visAcc + dt
			if acc >= 0.05 then
				acc = 0
				local w = math.sin(os.clock() * PULSE_SPEED) * PULSE_AMOUNT
				for _, f in ipairs(fills) do
					if f.a.Parent then f.a.Transparency = math.clamp(f.base + w, 0, 1) end
				end
			end
			if visAcc >= 0.5 then
				visAcc = 0
				updateVisibilityEsp()
				applyTheme()
			end
		end)
	end

	updateVisibilityEsp()
	applyTheme()

	_G.__PodiumESPCleanup = function()
		alive = false
		for _, c in ipairs(podiumConns) do pcall(function() c:Disconnect() end) end
		table.clear(podiumConns)
		clearPodium()
		_G.__PodiumESPCleanup = nil
	end
end


--------------------------------------------------
-- 8. Job ID 直接コピー機能の処理
--------------------------------------------------
local function copyJobIdDirectly(button)
	local jobId = game.JobId

	local function copyToClipboard(text)
		if typeof(setclipboard) == "function" then
			local ok = pcall(setclipboard, text)
			if ok then return true end
		end
		if typeof(toclipboard) == "function" then
			local ok = pcall(toclipboard, text)
			if ok then return true end
		end
		if syn and syn.clipboard and typeof(syn.clipboard.set) == "function" then
			local ok = pcall(syn.clipboard.set, text)
			if ok then return true end
		end
		if Clipboard and typeof(Clipboard.set) == "function" then
			local ok = pcall(Clipboard.set, text)
			if ok then return true end
		end
		if typeof(set_clipboard) == "function" then
			local ok = pcall(set_clipboard, text)
			if ok then return true end
		end
		return false
	end

	local copied = copyToClipboard(jobId)
	
	local originalText = button.Text
	local originalColor = button.BackgroundColor3
	
	if copied then
		button.Text = "Copied!"
		button.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	else
		button.Text = "Failed"
		button.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
	end
	
	task.delay(1.5, function()
		if button and button.Parent then
			button.Text = originalText
			button.BackgroundColor3 = originalColor
		end
	end)
end


--------------------------------------------------
-- 9. Auto-Kick 機能の処理（オン/オフ対応）
--------------------------------------------------
local autoKickEnabled = false
local autoKickConnections = {}

local function startAutoKick()
	local PlayerGui = player:WaitForChild("PlayerGui")
	local KEYWORD = "you stole"
	local KICK_MESSAGE = "YAMADAHUB ON TOP"

	local function hasKeyword(text)
		if typeof(text) ~= "string" then return false end
		return string.find(string.lower(text), KEYWORD) ~= nil
	end

	local function kick()
		pcall(function()
			player:Kick(KICK_MESSAGE)
		end)
	end

	local function watchObject(obj)
		if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
			return
		end
		if hasKeyword(obj.Text) then
			kick()
			return
		end
		local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
			if hasKeyword(obj.Text) then
				kick()
			end
		end)
		table.insert(autoKickConnections, conn)
	end

	local function scan(parent)
		for _, obj in ipairs(parent:GetDescendants()) do
			watchObject(obj)
		end
	end

	local function watchGui(gui)
		scan(gui)
		local conn = gui.DescendantAdded:Connect(function(desc)
			watchObject(desc)
		end)
		table.insert(autoKickConnections, conn)
	end

	for _, gui in ipairs(PlayerGui:GetChildren()) do
		watchGui(gui)
	end

	table.insert(autoKickConnections,
		PlayerGui.ChildAdded:Connect(function(gui)
			watchGui(gui)
		end)
	)
end

local function stopAutoKick()
	for _, conn in ipairs(autoKickConnections) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(autoKickConnections)
end

local function toggleAutoKick()
	autoKickEnabled = not autoKickEnabled
	if autoKickEnabled then
		startAutoKick()
	else
		stopAutoKick()
	end
end


--------------------------------------------------
-- 10. 統合機能コントロールUIの作成
--------------------------------------------------
local function createUnifiedUI()
	local oldGui = player.PlayerGui:FindFirstChild("SpeedControlGui")
	if oldGui then oldGui:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SpeedControlGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player.PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 160, 0, 255)
	frame.Position = UDim2.new(0, 10, 0, 10)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 115, 0, 25)
	label.Position = UDim2.new(0, 8, 0, 3)
	label.BackgroundTransparency = 1
	label.Text = "機能コントロール"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 12
	label.Font = Enum.Font.SourceSansBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local toggleButton = Instance.new("TextButton")
	toggleButton.Size = UDim2.new(0, 25, 0, 25)
	toggleButton.Position = UDim2.new(1, -28, 0, 3)
	toggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleButton.Text = "-"
	toggleButton.TextSize = 14
	toggleButton.Font = Enum.Font.SourceSansBold
	toggleButton.Parent = frame

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = toggleButton

	local contentContainer = Instance.new("Frame")
	contentContainer.Size = UDim2.new(1, 0, 0, 222)
	contentContainer.Position = UDim2.new(0, 0, 0, 30)
	contentContainer.BackgroundTransparency = 1
	contentContainer.Parent = frame

	local speedButton = Instance.new("TextButton")
	speedButton.Size = UDim2.new(0.9, 0, 0, 32)
	speedButton.Position = UDim2.new(0.05, 0, 0, 4)
	speedButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	speedButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	speedButton.Text = "Speed: " .. tostring(currentSpeed)
	speedButton.TextSize = 13
	speedButton.Font = Enum.Font.SourceSansBold
	speedButton.Parent = contentContainer
	
	speedButtonRef = speedButton

	local speedCorner = Instance.new("UICorner")
	speedCorner.CornerRadius = UDim.new(0, 4)
	speedCorner.Parent = speedButton

	speedButton.MouseButton1Click:Connect(function()
		if currentSpeed == DEFAULT_SPEED then
			currentSpeed = 100
		elseif currentSpeed == 100 then
			currentSpeed = 150
		else
			currentSpeed = DEFAULT_SPEED
		end
		speedButton.Text = "Speed: " .. tostring(currentSpeed)
	end)

	local carrieButton = Instance.new("TextButton")
	carrieButton.Size = UDim2.new(0.9, 0, 0, 35)
	carrieButton.Position = UDim2.new(0.05, 0, 0, 42)
	carrieButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	carrieButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	carrieButton.Text = "Carrie mode: OFF"
	carrieButton.TextSize = 13
	carrieButton.Font = Enum.Font.SourceSansBold
	carrieButton.Parent = contentContainer

	local carrieCorner = Instance.new("UICorner")
	carrieCorner.CornerRadius = UDim.new(0, 4)
	carrieCorner.Parent = carrieButton
	
	carrieButtonRef = carrieButton

	carrieButton.MouseButton1Click:Connect(function()
		setCarrieMode(not isCarrieMode)
	end)

	local xrayButton = Instance.new("TextButton")
	xrayButton.Size = UDim2.new(0.9, 0, 0, 35)
	xrayButton.Position = UDim2.new(0.05, 0, 0, 83)
	xrayButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	xrayButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	xrayButton.Text = "X-Ray: OFF"
	xrayButton.TextSize = 13
	xrayButton.Font = Enum.Font.SourceSansBold
	xrayButton.Parent = contentContainer

	local xrayCorner = Instance.new("UICorner")
	xrayCorner.CornerRadius = UDim.new(0, 4)
	xrayCorner.Parent = xrayButton

	xrayButton.MouseButton1Click:Connect(function()
		toggleXRay()
		if xrayEnabled then
			xrayButton.Text = "X-Ray: ON"
			xrayButton.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
		else
			xrayButton.Text = "X-Ray: OFF"
			xrayButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end
	end)

	local autoKickButton = Instance.new("TextButton")
	autoKickButton.Size = UDim2.new(0.9, 0, 0, 35)
	autoKickButton.Position = UDim2.new(0.05, 0, 0, 124)
	autoKickButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	autoKickButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	autoKickButton.Text = "Auto-Kick: OFF"
	autoKickButton.TextSize = 13
	autoKickButton.Font = Enum.Font.SourceSansBold
	autoKickButton.Parent = contentContainer

	local autoKickCorner = Instance.new("UICorner")
	autoKickCorner.CornerRadius = UDim.new(0, 4)
	autoKickCorner.Parent = autoKickButton

	autoKickButton.MouseButton1Click:Connect(function()
		toggleAutoKick()
		if autoKickEnabled then
			autoKickButton.Text = "Auto-Kick: ON"
			autoKickButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
		else
			autoKickButton.Text = "Auto-Kick: OFF"
			autoKickButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end
	end)

	local jobIdButton = Instance.new("TextButton")
	jobIdButton.Size = UDim2.new(0.9, 0, 0, 35)
	jobIdButton.Position = UDim2.new(0.05, 0, 0, 165)
	jobIdButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	jobIdButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	jobIdButton.Text = "Copy Job ID"
	jobIdButton.TextSize = 13
	jobIdButton.Font = Enum.Font.SourceSansBold
	jobIdButton.Parent = contentContainer

	local jobIdCorner = Instance.new("UICorner")
	jobIdCorner.CornerRadius = UDim.new(0, 4)
	jobIdCorner.Parent = jobIdButton

	jobIdButton.MouseButton1Click:Connect(function()
		copyJobIdDirectly(jobIdButton)
	end)

	local isOpen = true
	toggleButton.MouseButton1Click:Connect(function()
		isOpen = not isOpen
		if isOpen then
			frame.Size = UDim2.new(0, 160, 0, 255)
			contentContainer.Visible = true
			toggleButton.Text = "-"
		else
			frame.Size = UDim2.new(0, 160, 0, 30)
			contentContainer.Visible = false
			toggleButton.Text = "+"
		end
	end)
end


--------------------------------------------------
-- 11. 初期化実行
--------------------------------------------------
createUnifiedUI()
startAutoSteal()
initNextBaseTracker()
initPodiumESP()

if player.Character then
	task.spawn(function()
		onCharacterAdded(player.Character)
	end)
end

player.CharacterAdded:Connect(function(char)
	task.spawn(function()
		onCharacterAdded(char)
	end)
end)
