local library = sharedRequire('UILibrary.lua');

local AudioPlayer = sharedRequire('utils/AudioPlayer.lua');
local makeESP = sharedRequire('utils/makeESP.lua');

local Utility = sharedRequire('utils/Utility.lua');
local Maid = sharedRequire('utils/Maid.lua');
local AnalyticsAPI = sharedRequire('classes/AnalyticsAPI.lua');

local Services = sharedRequire('utils/Services.lua');
local createBaseESP = sharedRequire('utils/createBaseESP.lua');

local EntityESP = sharedRequire('classes/EntityESP.lua');
local ControlModule = sharedRequire('classes/ControlModule.lua');
local ToastNotif = sharedRequire('classes/ToastNotif.lua');

local prettyPrint = sharedRequire('utils/prettyPrint.lua');
local BlockUtils = sharedRequire('utils/BlockUtils.lua');
local TextLogger = sharedRequire('classes/TextLogger.lua');
local fromHex = sharedRequire('utils/fromHex.lua');
local toCamelCase = sharedRequire('utils/toCamelCase.lua');
local Webhook = sharedRequire('utils/Webhook.lua');

local column1, column2 = unpack(library.columns);

local functions = {};

local Players, RunService, UserInputService, CollectionService, TweenService = Services:Get('Players', 'RunService', 'UserInputService', 'CollectionService', 'TweenService');

Players = cloneref(Players);
RunService = cloneref(RunService);
UserInputService = cloneref(UserInputService);
CollectionService = cloneref(CollectionService);
TweenService = cloneref(TweenService);

local BLOCKED_PLACES: {[number]: string} = {
	[1] = 'Script will not run in menu!',
};

local blockedMessage: string? = BLOCKED_PLACES[game.PlaceId];
if (blockedMessage) then
	ToastNotif.new({ text = blockedMessage :: string, duration = 5 });
	task.delay(0.005, function(): ()
		library:Unload();
	end);
	return;
end;

local LocalPlayer: Player = Players.LocalPlayer;

local maid = Maid.new();

local ATTACH_MAX_RANGE: number = 300;

local localCheats = column1:AddSection('Local Cheats');
local combat = column2:AddSection('Combat');

-- known mob names sorted longest first so longer matches take priority
local MOB_NAMES: {string} = {
	'Corrupt Police Officer',
	'Speedwagon Agent',
	'Elite Mafia Member',
	'Hamon Apprentice',
	'Zombie Rudi von Stroheim',
	'Samurai Master',
	'Cultist Leader',
	'Rogue Rock Human',
	'Prison Escapee',
	'Elite Vampire',
	'Hamon Master',
	'Boxing Coach',
	'Mafia Member',
	'Akira Otoishi',
	'Delinquent',
	'Trinket',
	'Cultist',
	'Vampire',
	'Zombie',
	'Boxer',
	'Thief',
	'Thug',
	'rat',
};

--[[
	strips the leading dot and matches against known mob names.
	falls back to regex cleanup if no known name matches
]]
local function formatMobName(mobName: string): string
	-- strip leading dot
	local stripped: string = mobName:match('^%.(.+)') or mobName;

	-- try to match a known mob name (longest first)
	for _, name: string in MOB_NAMES do
		if (stripped:sub(1, #name) == name) then
			return name;
		end;
	end;

	-- fallback: strip trailing mixed junk after last lowercase letter
	local words: {string} = stripped:split(' ');
	local lastWord: string = words[#words];
	local cleaned: string? = lastWord:match('^(.-%l)%u');
	if (cleaned and #cleaned >= 2) then
		words[#words] = cleaned;
	end;

	return table.concat(words, ' ');
end;

local function onNewMobAdded(mob: Instance, espConstructor: any): ()
	-- skip player characters and non-dot entities
	if (not mob.Name:match('^%.')) then return end;

	local formattedName: string = formatMobName(mob.Name);

	-- check if this mob type is selected in the filter list
	if (library.flags.mobFilter and not library.flags.mobFilter[formattedName]) then return end;

	local code: string = [[
		local mob = ...;
		local FindFirstChild = game.FindFirstChild;
		local FindFirstChildWhichIsA = game.FindFirstChildWhichIsA;

		return setmetatable({
			FindFirstChildWhichIsA = function(_, ...)
				return FindFirstChildWhichIsA(mob, ...);
			end,
		}, {
			__index = function(_, p)
				if (p == 'Position') then
					local mobRoot = FindFirstChild(mob, 'HumanoidRootPart');
					return mobRoot and mobRoot.Position;
				end;
			end,
		})
	]];

	local mobEsp = espConstructor.new({code = code, vars = {mob}}, formattedName);

	local connection: RBXScriptConnection;
	connection = mob:GetPropertyChangedSignal('Parent'):Connect(function(): ()
		if (not mob.Parent) then
			connection:Disconnect();
			mobEsp:Destroy();
		end;
	end);
end;

function functions.fly(toggle: boolean): ()
	if (not toggle) then
		maid.flyHack = nil;
		maid.flyBv = nil;
		return;
	end;

	maid.flyBv = Instance.new('BodyVelocity');
	maid.flyBv.MaxForce = Vector3.new(math.huge, math.huge, math.huge);

	maid.flyHack = RunService.Heartbeat:Connect(function(): ()
		local playerData = Utility:getPlayerData();
		local rootPart: BasePart?, camera: Camera? = playerData.rootPart, workspace.CurrentCamera;
		if (not rootPart or not camera) then return end;

		if (not CollectionService:HasTag(maid.flyBv, 'AllowedBM')) then
			CollectionService:AddTag(maid.flyBv, 'AllowedBM');
		end;

		maid.flyBv.Parent = rootPart;
		maid.flyBv.Velocity = (camera :: Camera).CFrame:VectorToWorldSpace(ControlModule:GetMoveVector() * library.flags.flyHackValue);
	end);
end;

function functions.speedHack(toggle: boolean): ()
	if (not toggle) then
		maid.speedHack = nil;
		maid.speedHackBv = nil;
		return;
	end;

	maid.speedHack = RunService.Heartbeat:Connect(function(): ()
		local playerData = Utility:getPlayerData();
		local humanoid: Humanoid?, rootPart: BasePart? = playerData.humanoid, playerData.primaryPart;
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
		maid.speedHackBv.Velocity = ((humanoid :: Humanoid).MoveDirection.Magnitude ~= 0 and (humanoid :: Humanoid).MoveDirection or gethiddenproperty(humanoid :: Humanoid, 'WalkDirection')) * library.flags.speedHackValue;
	end);
end;

function functions.infiniteJump(toggle: boolean): ()
	if (not toggle) then return end;

	repeat
		local rootPart: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
		if (rootPart and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
			(rootPart :: any).Velocity = Vector3.new((rootPart :: any).Velocity.X, library.flags.infiniteJumpHeight, (rootPart :: any).Velocity.Z);
		end;
		task.wait(0.1);
	until (not library.flags.infiniteJump);
end;

function functions.noClip(toggle: boolean): ()
	if (not toggle) then
		maid.noClip = nil;

		local humanoid: Humanoid? = Utility:getPlayerData().humanoid;
		if (not humanoid) then return end;

		(humanoid :: Humanoid):ChangeState('Physics');
		task.wait();
		(humanoid :: Humanoid):ChangeState('RunningNoPhysics');
		return;
	end;

	maid.noClip = RunService.Stepped:Connect(function(): ()
		local myCharacterParts = Utility:getPlayerData().parts;

		for _, v: BasePart in myCharacterParts do
			v.CanCollide = false;
		end;
	end);
end;

-- one shot mobs, ported from deepwoken. drops them below the destroy height
-- so the server kills them instantly
do
	local mobs: {[Model]: any} = {};

	local NetworkOneShot = {};
	NetworkOneShot.__index = NetworkOneShot;

	function NetworkOneShot.new(mob: Model): any
		local self = setmetatable({}, NetworkOneShot);

		self._maid = Maid.new();
		self.char = mob;

		self._maid:GiveTask(mob.Destroying:Connect(function(): ()
			self:Destroy();
		end));

		self._maid:GiveTask(Utility.listenToChildAdded(mob, function(obj: Instance): ()
			if (obj.Name == 'HumanoidRootPart' and obj:IsA('BasePart')) then
				self.hrp = obj :: BasePart;
			end;
		end));

		mobs[mob] = self;
		return self;
	end;

	function NetworkOneShot:Update(): ()
		if (not self.hrp or not self.hrp.Parent) then return end;

		local ok: boolean, owned: boolean? = pcall(isnetworkowner, self.hrp);
		if (not ok or not owned) then return end;

		local parent: Instance? = self.hrp.Parent;
		if (not parent or (parent :: Instance).Parent ~= workspace.Live) then return end;

		self.char:PivotTo(CFrame.new(self.hrp.Position.X, workspace.FallenPartsDestroyHeight - 100000, self.hrp.Position.Z));
	end;

	function NetworkOneShot:Destroy(): ()
		self._maid:DoCleaning();

		for i, v in next, mobs do
			if (v ~= self) then continue end;
			mobs[i] = nil;
		end;
	end;

	function NetworkOneShot.ClearAll(): ()
		for _, v in next, mobs do
			v:Destroy();
		end;

		table.clear(mobs);
	end;

	local liveFolder: Folder = workspace:WaitForChild('Live');

	Utility.listenToChildAdded(liveFolder, function(obj: Instance): ()
		task.wait(0.2);
		if (obj == LocalPlayer.Character) then return end;
		NetworkOneShot.new(obj :: Model);
	end);

	function functions.networkOneShot(toggle: boolean): ()
		if (not toggle) then
			maid.networkOneShot = nil;
			maid.networkOneShotSim = nil;
			return;
		end;

		maid.networkOneShotSim = RunService.Heartbeat:Connect(function(): ()
			sethiddenproperty(LocalPlayer, 'MaxSimulationRadius', math.huge);
			sethiddenproperty(LocalPlayer, 'SimulationRadius', math.huge);
		end);

		maid.networkOneShot = task.spawn(function(): ()
			while task.wait() do
				for _, mob: any in next, mobs do
					mob:Update();
				end;
			end;
		end);
	end;
end;

library.OnKeyPress:Connect(function(input: InputObject, gpe: boolean): ()
	if (gpe or not library.options.attachToBack) then return end;

	local key = library.options.attachToBack.key;
	if (input.KeyCode.Name ~= key and input.UserInputType.Name ~= key) then return end;

	local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
	if (not hrp) then return end;

	local closest: BasePart?, closestDistance: number = nil, math.huge;

	repeat
		for _, entity: Instance in (workspace :: any).Live:GetChildren() do
			local rootPart: BasePart? = entity:FindFirstChild('HumanoidRootPart') :: BasePart?;
			if (not rootPart or rootPart == hrp) then continue end;

			local distance: number = ((rootPart :: BasePart).Position - (hrp :: BasePart).Position).Magnitude;

			if (distance < ATTACH_MAX_RANGE and distance < closestDistance) then
				closest, closestDistance = rootPart, distance;
			end;
		end;

		task.wait();
	until (closest or input.UserInputState == Enum.UserInputState.End);
	if (input.UserInputState == Enum.UserInputState.End) then return end;

	local lastGoalPos: Vector3? = nil;

	maid.attachToBack = RunService.Heartbeat:Connect(function(): ()
		local goalCF: CFrame = (closest :: BasePart).CFrame * CFrame.new(0, library.flags.attachToBackHeight, library.flags.attachToBackSpace);

		if (lastGoalPos and (goalCF.Position - lastGoalPos :: Vector3).Magnitude < 0.5) then return end;
		lastGoalPos = goalCF.Position;

		local distance: number = (goalCF.Position - (hrp :: BasePart).Position).Magnitude;
		local tween: Tween = TweenService:Create(hrp, TweenInfo.new(distance / 100, Enum.EasingStyle.Linear), {
			CFrame = goalCF
		});

		tween:Play();

		maid.attachToBackTween = function(): ()
			tween:Cancel();
		end;
	end);
end);

library.OnKeyRelease:Connect(function(input: InputObject): ()
	if (not library.options.attachToBack) then return end;
	local key = library.options.attachToBack.key;

	if (input.KeyCode.Name == key or input.UserInputType.Name == key) then
		maid.attachToBack = nil;
		maid.attachToBackTween = nil;
	end;
end);

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
	text = 'Infinite Jump',
	callback = functions.infiniteJump
});

localCheats:AddSlider({
	min = 50,
	max = 250,
	flag = 'Infinite Jump Height',
	textpos = 2
});

localCheats:AddToggle({
	text = 'No Clip',
	callback = functions.noClip
});

localCheats:AddDivider('Utility');

localCheats:AddBind({
	text = 'Attach To Back',
	tip = 'Attaches to the nearest entity based on settings',
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

combat:AddToggle({
	text = 'One Shot Mobs',
	tip = 'claims network ownership and drops mobs below the kill plane',
	callback = functions.networkOneShot
});

function Utility:renderOverload(data: any): ()
	makeESP({
		sectionName = 'Mobs',
		type = 'childAdded',
		args = workspace:WaitForChild('Live'),
		callback = onNewMobAdded,
		onLoaded = function(section: any): ()
			section:AddToggle({
				text = 'Show Health',
				flag = 'Mobs Show Health'
			});

			section:AddList({
				text = 'Mob Filter',
				multiselect = true,
				values = MOB_NAMES,
			});
		end
	});
end;
