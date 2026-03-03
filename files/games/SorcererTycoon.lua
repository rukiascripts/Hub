--[[ @author jacob ]]

local library = sharedRequire('UILibrary.lua');

local Utility = sharedRequire('utils/Utility.lua');
local Maid = sharedRequire('utils/Maid.lua');
local Services = sharedRequire('utils/Services.lua');
local ControlModule = sharedRequire('classes/ControlModule.lua');
local ToastNotif = sharedRequire('classes/ToastNotif.lua');

local column1, column2 = unpack(library.columns);

local functions = {};

local Players, RunService, UserInputService, CollectionService, TweenService, VirtualInputManager = Services:Get('Players', 'RunService', 'UserInputService', 'CollectionService', 'TweenService', 'VirtualInputManager');
local LocalPlayer = Players.LocalPlayer;

local maid = Maid.new();

local MOB_SEARCH_RADIUS = 300;
local DROPS_SCAN_INTERVAL = 0.5;
local DROPS_PICKUP_DELAY = 0.1;
local FARM_TICK_DELAY = 0.15;
local ANTI_AFK_INTERVAL = 60;

local map = workspace:WaitForChild('Map');
local npcSpawns = map:WaitForChild('NPCs'):WaitForChild('Spawns');
local bossFolder = map:WaitForChild('Boss');

local killCount = 0;
local bossKillCount = 0;
local dropsCollected = 0;

local localCheats = column1:AddSection('Local Cheats');
local automation = column2:AddSection('Automation');

do -- // Movement
	function functions.fly(toggle)
		if (not toggle) then
			maid.flyHack = nil;
			maid.flyBv = nil;

			return;
		end;

		maid.flyBv = Instance.new('BodyVelocity');
		maid.flyBv.MaxForce = Vector3.new(math.huge, math.huge, math.huge);

		maid.flyHack = RunService.Heartbeat:Connect(function()
			local playerData = Utility:getPlayerData();
			local rootPart, camera = playerData.rootPart, workspace.CurrentCamera;
			if (not rootPart or not camera) then return end;

			if (not CollectionService:HasTag(maid.flyBv, 'AllowedBM')) then
				CollectionService:AddTag(maid.flyBv, 'AllowedBM');
			end;

			maid.flyBv.Parent = rootPart;
			maid.flyBv.Velocity = camera.CFrame:VectorToWorldSpace(ControlModule:GetMoveVector() * library.flags.flyHackValue);
		end);
	end;

	function functions.speedHack(toggle)
		if (not toggle) then
			maid.speedHack = nil;
			maid.speedHackBv = nil;

			return;
		end;

		maid.speedHack = RunService.Heartbeat:Connect(function()
			local playerData = Utility:getPlayerData();
			local humanoid, rootPart = playerData.humanoid, playerData.primaryPart;
			if (not humanoid or not rootPart) then return end;

			if (library.flags.fly) then
				maid.speedHackBv = nil;
				return;
			end;

			maid.speedHackBv = maid.speedHackBv or Instance.new('BodyVelocity');
			maid.speedHackBv.MaxForce = Vector3.new(100000, 0, 100000);

			if (not CollectionService:HasTag(maid.speedHackBv, 'AllowedBM')) then
				CollectionService:AddTag(maid.speedHackBv, 'AllowedBM');
			end;

			maid.speedHackBv.Parent = not library.flags.fly and rootPart or nil;
			maid.speedHackBv.Velocity = (humanoid.MoveDirection.Magnitude ~= 0 and humanoid.MoveDirection or gethiddenproperty(humanoid, 'WalkDirection')) * library.flags.speedHackValue;
		end);
	end;

	function functions.noClip(toggle)
		if (not toggle) then
			maid.noClip = nil;

			local humanoid = Utility:getPlayerData().humanoid;
			if (not humanoid) then return end;

			humanoid:ChangeState('Physics');
			task.wait();
			humanoid:ChangeState('RunningNoPhysics');

			return;
		end;

		maid.noClip = RunService.Stepped:Connect(function()
			local myCharacterParts = Utility:getPlayerData().parts;

			for _, v in next, myCharacterParts do
				v.CanCollide = false;
			end;
		end);
	end;
end;

do -- // Attach To Back
	function functions.attachToBack()
		library.OnKeyPress:Connect(function(input, gpe)
			if (gpe) then return end;

			local key = library.options.attachToBack.key;
			if (input.KeyCode.Name ~= key and input.UserInputType.Name ~= key) then return end;

			local myRootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');
			if (not myRootPart) then return end;

			local closest, closestDistance = nil, math.huge;

			repeat
				for _, descendant in map:GetDescendants() do
					if (descendant.Name ~= 'HumanoidRootPart' or descendant == myRootPart) then continue end;

					local distance = (descendant.Position - myRootPart.Position).Magnitude;

					if (distance < MOB_SEARCH_RADIUS and distance < closestDistance) then
						closest, closestDistance = descendant, distance;
					end;
				end;

				task.wait();
			until closest or input.UserInputState == Enum.UserInputState.End;
			if (input.UserInputState == Enum.UserInputState.End) then return end;

			maid.attachToBack = RunService.Heartbeat:Connect(function()
				local goalCF = closest.CFrame * CFrame.new(0, library.flags.attachToBackHeight, library.flags.attachToBackSpace);

				local distance = (goalCF.Position - myRootPart.Position).Magnitude;
				local tweenInfo = TweenInfo.new(distance / 100, Enum.EasingStyle.Linear);

				local tween = TweenService:Create(myRootPart, tweenInfo, {
					CFrame = goalCF
				});

				tween:Play();

				maid.attachToBackTween = function()
					tween:Cancel();
				end;
			end);
		end);

		library.OnKeyRelease:Connect(function(input)
			local key = library.options.attachToBack.key;
			if (input.KeyCode.Name == key or input.UserInputType.Name == key) then
				maid.attachToBack = nil;
				maid.attachToBackTween = nil;
			end;
		end);
	end;
end;

do -- // Farming Helpers
	local ATTACK_KEYS = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four};
	local SKILL_FLAGS = {'useSkill1', 'useSkill2', 'useSkill3', 'useSkill4'};

	local STREAM_THRESHOLD = 50;

	--- streams content around a position if the player is far from it, yields until loaded
	local function ensureStreamed(rootPart, position)
		local distance = (rootPart.Position - position).Magnitude;
		if (distance < STREAM_THRESHOLD) then return end;
		LocalPlayer:RequestStreamAroundAsync(position);
		task.wait(0.5);
	end;

	--- positions rootPart above/below target, facing toward them on the Y axis only
	local function moveToTarget(rootPart, targetHrp, heightOffset)
		local targetPos = targetHrp.Position;
		local offsetPos = targetPos + Vector3.new(0, heightOffset, 0);

		-- face toward target horizontally (keep character upright)
		local flatLook = Vector3.new(targetPos.X, offsetPos.Y, targetPos.Z);

		if (not maid.farmBp) then
			local bp = Instance.new('BodyPosition');
			bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge);
			bp.D = 100;
			bp.P = 10000;
			bp.Parent = rootPart;
			maid.farmBp = bp;

			local bg = Instance.new('BodyGyro');
			bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge);
			bg.D = 50;
			bg.P = 5000;
			bg.Parent = rootPart;
			maid.farmBg = bg;
		end;

		maid.farmBp.Position = offsetPos;
		maid.farmBg.CFrame = CFrame.lookAt(offsetPos, flatLook);
	end;

	--- cleans up farm body movers
	local function cleanupMovers()
		maid.farmBp = nil;
		maid.farmBg = nil;
	end;

	local SKILL_DELAY_FLAGS = {'skill1Delay', 'skill2Delay', 'skill3Delay', 'skill4Delay'};

	--- gets sorted skill tools from backpack + character
	local function getSkillTools()
		local backpack = LocalPlayer:FindFirstChild('Backpack');
		local character = LocalPlayer.Character;
		if (not backpack) then return {} end;

		local tools = {};

		for _, tool in backpack:GetChildren() do
			if (tool:IsA('Tool')) then
				table.insert(tools, tool);
			end;
		end;

		if (character) then
			for _, tool in character:GetChildren() do
				if (tool:IsA('Tool')) then
					table.insert(tools, tool);
				end;
			end;
		end;

		table.sort(tools, function(a, b)
			return a.Name < b.Name;
		end);

		return tools;
	end;

	--- checks if the Nth skill tool is on cooldown (not in backpack or character)
	local function isSkillReady(slotIndex)
		local tools = getSkillTools();
		return tools[slotIndex] ~= nil;
	end;

	--- sends a key press for skills that are toggled on and ready
	local function attackWithKeys()
		for i, keyCode in ATTACK_KEYS do
			if (not library.flags[SKILL_FLAGS[i]]) then continue end;
			if (not isSkillReady(i)) then continue end;

			local delay = library.flags[SKILL_DELAY_FLAGS[i]] or 0.1;

			VirtualInputManager:SendKeyEvent(true, keyCode, false, game);
			task.wait(0.05);
			VirtualInputManager:SendKeyEvent(false, keyCode, false, game);
			task.wait(delay);
		end;
	end;

	--- finds a live NPC model inside an Info folder under npcSpawns
	local function findNPC()
		for _, info in npcSpawns:GetChildren() do
			local npcFolder = info:FindFirstChild('NPC');
			if (not npcFolder) then continue end;

			for _, mob in npcFolder:GetChildren() do
				local humanoid = mob:FindFirstChildOfClass('Humanoid');
				local hrp = mob:FindFirstChild('HumanoidRootPart');
				if (humanoid and humanoid.Health > 0 and hrp) then
					return mob, hrp, humanoid;
				end;
			end;
		end;

		return nil;
	end;

	--- finds a live boss model in the selected boss zone
	local function findBoss()
		local selectedZone = library.flags.bossZone;
		if (not selectedZone or selectedZone == 'None') then return nil end;

		local zoneFolder = bossFolder:FindFirstChild(selectedZone);
		if (not zoneFolder) then return nil end;

		local bossesFolder = zoneFolder:FindFirstChild('Bosses');
		if (not bossesFolder or #bossesFolder:GetChildren() == 0) then return nil end;

		for _, mob in bossesFolder:GetChildren() do
			local humanoid = mob:FindFirstChildOfClass('Humanoid');
			local hrp = mob:FindFirstChild('HumanoidRootPart');
			if (humanoid and humanoid.Health > 0 and hrp) then
				return mob, hrp, humanoid;
			end;
		end;

		return nil;
	end;

	--- gets the CFrame of an instance whether it's a BasePart or Model
	local function getCFrame(instance)
		if (instance:IsA('BasePart')) then return instance.CFrame end;
		if (instance:IsA('Model')) then return instance:GetPivot() end;
		return nil;
	end;

	--- checks if an instance is inside a Drops folder
	local function isInsideDropsFolder(instance)
		local current = instance.Parent;

		while (current and current ~= map) do
			if (current.Name == 'Drops') then return true end;
			current = current.Parent;
		end;

		return false;
	end;

	--- collects drops from a specific Drops folder
	local function collectDropsFrom(dropsFolder, rootPart)
		if (not dropsFolder or not rootPart) then return end;

		for _, drop in dropsFolder:GetDescendants() do
			if (not drop:IsA('ProximityPrompt')) then continue end;

			local dropParent = drop.Parent;
			if (not dropParent) then continue end;

			local cf = getCFrame(dropParent);
			if (not cf) then continue end;
			
			if (drop.Parent.Name ~= 'Yen' and drop.Parent.Name ~= 'CursedEnergy') then continue end;

			rootPart.CFrame = cf;
			fireproximityprompt(drop);
			dropsCollected += 1;
			task.wait(DROPS_PICKUP_DELAY);
		end;
	end;

	function functions.autoFarmNPCs(toggle)
		if (not toggle) then
			maid.autoFarmNPCs = nil;
			cleanupMovers();
			return;
		end;

		maid.autoFarmNPCs = task.spawn(function()
			while (true) do
				-- bosses take priority when both are enabled and a zone is selected
				local bossZone = library.flags.bossZone;
				if (library.flags.autoFarmBosses and bossZone and bossZone ~= 'None' and findBoss()) then
					cleanupMovers();
					task.wait(0.5);
					continue;
				end;

				local rootPart = Utility:getPlayerData().rootPart;
				if (not rootPart) then
					task.wait(0.5);
					continue;
				end;

				local mob, hrp, humanoid = findNPC();
				if (not mob or not hrp) then
					cleanupMovers();
					task.wait(0.5);
					continue;
				end;

				ensureStreamed(rootPart, hrp.Position);

				repeat
					moveToTarget(rootPart, hrp, library.flags.farmHeightOffset);
					attackWithKeys();
					task.wait(FARM_TICK_DELAY);
				until not humanoid or humanoid.Health <= 0 or not hrp.Parent;

				cleanupMovers();

				if (humanoid and humanoid.Health <= 0) then
					killCount += 1;

					if (library.flags.autoCollectDrops) then
						for _, info in npcSpawns:GetChildren() do
							local dropsFolder = info:FindFirstChild('Drops');
							collectDropsFrom(dropsFolder, rootPart);
						end;
					end;
				end;

				task.wait(0.3);
			end;
		end);
	end;

	function functions.autoFarmBosses(toggle)
		if (not toggle) then
			maid.autoFarmBosses = nil;
			cleanupMovers();
			return;
		end;

		maid.autoFarmBosses = task.spawn(function()
			while (true) do
				local rootPart = Utility:getPlayerData().rootPart;
				if (not rootPart) then
					task.wait(0.5);
					continue;
				end;

				local selectedZone = library.flags.bossZone;
				if (not selectedZone or selectedZone == 'None') then
					cleanupMovers();
					task.wait(1);
					continue;
				end;

				local mob, hrp, humanoid = findBoss();
				if (not mob or not hrp) then
					cleanupMovers();
					task.wait(1);
					continue;
				end;

				ensureStreamed(rootPart, hrp.Position);

				repeat
					moveToTarget(rootPart, hrp, library.flags.farmHeightOffset);
					attackWithKeys();
					task.wait(FARM_TICK_DELAY);
				until not humanoid or humanoid.Health <= 0 or not hrp.Parent;

				cleanupMovers();

				if (humanoid and humanoid.Health <= 0) then
					bossKillCount += 1;

					if (library.flags.autoCollectDrops) then
						local zoneFolder = bossFolder:FindFirstChild(selectedZone);
						if (zoneFolder) then
							collectDropsFrom(zoneFolder:FindFirstChild('Drops'), rootPart);
						end;
					end;
				end;

				task.wait(0.3);
			end;
		end);
	end;

	function functions.autoCollectDrops(toggle)
		if (not toggle) then
			maid.autoCollectDrops = nil;
			return;
		end;

		maid.autoCollectDrops = task.spawn(function()
			while task.wait(DROPS_SCAN_INTERVAL) do
				if (not library.flags.autoCollectDrops) then break end;

				local rootPart = Utility:getPlayerData().rootPart;
				if (not rootPart) then continue end;

				for _, child in map:GetDescendants() do
					if (not library.flags.autoCollectDrops) then break end;
					if (not child:IsA('ProximityPrompt')) then continue end;
					if (not isInsideDropsFolder(child)) then continue end;

					local dropParent = child.Parent;
					if (not dropParent) then continue end;

					local cf = getCFrame(dropParent);
					if (not cf) then continue end;

					if (dropParent.Name ~= 'Yen' and dropParent.Name ~= 'CursedEnergy') then continue end;

					rootPart.CFrame = cf;
					fireproximityprompt(child);
					dropsCollected += 1;
					task.wait(DROPS_PICKUP_DELAY);
				end;
			end;
		end);
	end;
end;

do -- // Kill Counter
	function functions.showStats()
		ToastNotif.new({
			text = `NPC Kills: {killCount} | Boss Kills: {bossKillCount} | Drops: {dropsCollected}`,
			duration = 5
		});
	end;

	function functions.resetStats()
		killCount = 0;
		bossKillCount = 0;
		dropsCollected = 0;

		ToastNotif.new({
			text = 'Stats reset!',
			duration = 3
		});
	end;
end;

do -- // Anti-AFK
	function functions.antiAfk(toggle)
		if (not toggle) then
			maid.antiAfk = nil;
			return;
		end;

		maid.antiAfk = task.spawn(function()
			while task.wait(ANTI_AFK_INTERVAL) do
				if (not library.flags.antiAfk) then break end;
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game);
				task.wait(0.1);
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game);
			end;
		end);
	end;
end;

do -- // Boss Zone List
	local bossZones = {'None'};

	for _, zone in bossFolder:GetChildren() do
		table.insert(bossZones, zone.Name);
	end;

	-- // UI Registration
	localCheats:AddDivider('Movement');

	localCheats:AddToggle({
		text = 'Fly',
		callback = functions.fly
	});

	localCheats:AddSlider({
		flag = 'Fly Hack Value',
		min = 16,
		max = 250,
		value = 50,
		textpos = 2
	});

	localCheats:AddToggle({
		text = 'Speedhack',
		callback = functions.speedHack
	});

	localCheats:AddSlider({
		flag = 'Speed Hack Value',
		min = 16,
		max = 250,
		value = 50,
		textpos = 2
	});

	localCheats:AddToggle({
		text = 'No Clip',
		callback = functions.noClip
	});

	localCheats:AddBind({
		text = 'Attach To Back',
		tip = 'Attaches to the nearest entity based on settings',
		callback = functions.attachToBack
	});

	localCheats:AddSlider({
		text = 'Attach To Back Height',
		value = 0,
		min = -100,
		max = 100,
		textpos = 2
	});

	localCheats:AddSlider({
		text = 'Attach To Back Space',
		value = 2,
		min = -100,
		max = 100,
		textpos = 2
	});

	automation:AddDivider('NPC Farm');

	automation:AddToggle({
		text = 'Auto Farm NPCs',
		tip = 'Teleports to NPCs under Map.NPCs.Spawns and positions above/below them',
		callback = functions.autoFarmNPCs
	});

	automation:AddDivider('Boss Farm');

	automation:AddToggle({
		text = 'Auto Farm Bosses',
		tip = 'Farms bosses in the selected zone, prioritized over NPCs',
		callback = functions.autoFarmBosses
	});

	automation:AddList({
		text = 'Boss Zone',
		values = bossZones,
		value = 'None'
	});

	automation:AddDivider('Skills');

	automation:AddToggle({
		text = 'Use Skill 1',
		flag = 'Use Skill 1'
	});

	automation:AddSlider({
		text = 'Skill 1 Delay',
		flag = 'Skill 1 Delay',
		min = 0,
		max = 5,
		value = 0.1,
		textpos = 2
	});

	automation:AddToggle({
		text = 'Use Skill 2',
		flag = 'Use Skill 2'
	});

	automation:AddSlider({
		text = 'Skill 2 Delay',
		flag = 'Skill 2 Delay',
		min = 0,
		max = 5,
		value = 0.1,
		textpos = 2
	});

	automation:AddToggle({
		text = 'Use Skill 3',
		flag = 'Use Skill 3'
	});

	automation:AddSlider({
		text = 'Skill 3 Delay',
		flag = 'Skill 3 Delay',
		min = 0,
		max = 5,
		value = 0.1,
		textpos = 2
	});

	automation:AddToggle({
		text = 'Use Skill 4',
		flag = 'Use Skill 4'
	});

	automation:AddSlider({
		text = 'Skill 4 Delay',
		flag = 'Skill 4 Delay',
		min = 0,
		max = 5,
		value = 0.1,
		textpos = 2
	});

	automation:AddDivider('Farm Settings');

	automation:AddSlider({
		text = 'Farm Height Offset',
		tip = 'Positive = above (face down), Negative = below (face up)',
		flag = 'Farm Height Offset',
		min = -50,
		max = 50,
		value = 10,
		textpos = 2
	});

	automation:AddToggle({
		text = 'Auto Collect Drops',
		tip = 'Picks up drops from NPC/Boss Drops folders after kills',
		callback = functions.autoCollectDrops
	});

	automation:AddDivider('Utility');

	automation:AddToggle({
		text = 'Anti-AFK',
		tip = 'Prevents idle kick while farming',
		callback = functions.antiAfk
	});

	automation:AddButton({
		text = 'Show Stats',
		tip = 'Shows kill count and drops collected this session',
		callback = functions.showStats
	});

	automation:AddButton({
		text = 'Reset Stats',
		tip = 'Resets all kill/drop counters to zero',
		callback = functions.resetStats
	});
end;
