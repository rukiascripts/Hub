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

do -- // One Shot Mobs
	local mobs = {};

	local NetworkOneShot = {};
	NetworkOneShot.__index = NetworkOneShot;

	function NetworkOneShot.new(mob)
		local self = setmetatable({}, NetworkOneShot);

		self._maid = Maid.new();
		self.char = mob;

		self._maid:GiveTask(mob.Destroying:Connect(function()
			self:Destroy();
		end));

		self._maid:GiveTask(Utility.listenToChildAdded(mob, function(obj)
			if (obj.Name == 'HumanoidRootPart') then
				self.hrp = obj;
			end;
		end));

		mobs[mob] = self;
		return self;
	end;

	function NetworkOneShot:Update()
		if (not self.hrp or not isnetworkowner(self.hrp) or not self.hrp.Parent or not self.hrp:IsDescendantOf(map)) then return end;
		self.char:PivotTo(CFrame.new(self.hrp.Position.X, workspace.FallenPartsDestroyHeight - 100000, self.hrp.Position.Z));
	end;

	function NetworkOneShot:Destroy()
		self._maid:DoCleaning();

		for i, v in next, mobs do
			if (v ~= self) then continue end;
			mobs[i] = nil;
		end;
	end;

	function NetworkOneShot:ClearAll()
		for _, v in next, mobs do
			v:Destroy();
		end;

		table.clear(mobs);
	end;

	map.DescendantAdded:Connect(function(obj)
		if (obj.Name ~= 'Humanoid') then return end;

		local mob = obj.Parent;
		task.wait(0.2);
		if (not mob or mob == LocalPlayer.Character or mobs[mob]) then return end;
		NetworkOneShot.new(mob);
	end);

	for _, obj in map:GetDescendants() do
		if (obj.Name ~= 'Humanoid') then continue end;

		local mob = obj.Parent;
		if (not mob or mob == LocalPlayer.Character or mobs[mob]) then continue end;
		NetworkOneShot.new(mob);
	end;

	function functions.networkOneShot(toggle)
		if (not toggle) then
			maid.networkOneShot = nil;
			maid.networkOneShotSim = nil;
			return;
		end;

		maid.networkOneShotSim = RunService.Heartbeat:Connect(function()
			sethiddenproperty(LocalPlayer, 'MaxSimulationRadius', math.huge);
			sethiddenproperty(LocalPlayer, 'SimulationRadius', math.huge);
		end);

		maid.networkOneShot = task.spawn(function()
			while task.wait() do
				for _, mob in next, mobs do
					mob:Update();
				end;
			end;
		end);
	end;
end;

do -- // Farming Helpers
	--- positions rootPart above/below target facing toward them
	local function positionAtTarget(rootPart, targetHrp, heightOffset)
		local targetPos = targetHrp.Position;
		local offsetPos = targetPos + Vector3.new(0, heightOffset, 0);

		local lookDir = (targetPos - offsetPos).Unit;
		rootPart.CFrame = CFrame.lookAt(offsetPos, offsetPos + lookDir);
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

	--- collects drops from a specific Drops folder
	local function collectDropsFrom(dropsFolder, rootPart)
		if (not dropsFolder or not rootPart) then return end;

		for _, drop in dropsFolder:GetDescendants() do
			if (not drop:IsA('ProximityPrompt')) then continue end;

			local dropParent = drop.Parent;
			if (not dropParent) then continue end;

			rootPart.CFrame = dropParent.CFrame;
			fireproximityprompt(drop);
			dropsCollected += 1;
			task.wait(DROPS_PICKUP_DELAY);
		end;
	end;

	function functions.autoFarmNPCs(toggle)
		if (not toggle) then
			maid.autoFarmNPCs = nil;
			return;
		end;

		maid.autoFarmNPCs = task.spawn(function()
			while task.wait(FARM_TICK_DELAY) do
				if (not library.flags.autoFarmNPCs) then break end;

				-- bosses take priority when both are enabled
				if (library.flags.autoFarmBosses and findBoss()) then
					task.wait(0.5);
					continue;
				end;

				local rootPart = Utility:getPlayerData().rootPart;
				if (not rootPart) then continue end;

				local mob, hrp, humanoid = findNPC();
				if (not mob or not hrp) then continue end;

				local heightOffset = library.flags.farmHeightOffset;

				repeat
					positionAtTarget(rootPart, hrp, heightOffset);
					task.wait(FARM_TICK_DELAY);
				until not humanoid or humanoid.Health <= 0 or not library.flags.autoFarmNPCs or not hrp.Parent;

				if (humanoid and humanoid.Health <= 0) then
					killCount += 1;

					if (library.flags.autoCollectDrops) then
						for _, info in npcSpawns:GetChildren() do
							local dropsFolder = info:FindFirstChild('Drops');
							collectDropsFrom(dropsFolder, rootPart);
						end;
					end;
				end;
			end;
		end);
	end;

	function functions.autoFarmBosses(toggle)
		if (not toggle) then
			maid.autoFarmBosses = nil;
			return;
		end;

		maid.autoFarmBosses = task.spawn(function()
			while task.wait(FARM_TICK_DELAY) do
				if (not library.flags.autoFarmBosses) then break end;

				local rootPart = Utility:getPlayerData().rootPart;
				if (not rootPart) then continue end;

				local selectedZone = library.flags.bossZone;
				if (not selectedZone or selectedZone == 'None') then
					task.wait(1);
					continue;
				end;

				local mob, hrp, humanoid = findBoss();
				if (not mob or not hrp) then
					task.wait(1);
					continue;
				end;

				local heightOffset = library.flags.farmHeightOffset;

				repeat
					positionAtTarget(rootPart, hrp, heightOffset);
					task.wait(FARM_TICK_DELAY);
				until not humanoid or humanoid.Health <= 0 or not library.flags.autoFarmBosses or not hrp.Parent;

				if (humanoid and humanoid.Health <= 0) then
					bossKillCount += 1;

					if (library.flags.autoCollectDrops) then
						local zoneFolder = bossFolder:FindFirstChild(selectedZone);
						if (zoneFolder) then
							collectDropsFrom(zoneFolder:FindFirstChild('Drops'), rootPart);
						end;
					end;
				end;
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

					local dropParent = child.Parent;
					if (not dropParent) then continue end;

					rootPart.CFrame = dropParent.CFrame;
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

	automation:AddDivider('Kill Method');

	automation:AddToggle({
		text = 'Network One Shot',
		tip = 'Kills mobs by sending them below the death barrier',
		callback = functions.networkOneShot
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
