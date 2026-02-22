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

local Players, RunService, UserInputService, HttpService, CollectionService, MemStorageService, Lighting, TweenService, VirtualInputManager, ReplicatedFirst, TeleportService, ReplicatedStorage = Services:Get(
	'Players',
	'RunService',
	'UserInputService',
	'HttpService',
	'CollectionService',
	'MemStorageService',
	'Lighting',
	'TweenService',
	'VirtualInputManager',
	'ReplicatedFirst',
	'TeleportService',
	'ReplicatedStorage'
);

local LocalPlayer: Player = Players.LocalPlayer;
local playerMouse = LocalPlayer:GetMouse();

local column1, column2 = unpack(library.columns);

local maid = Maid.new();

local localCheats = column1:AddSection('Local Cheats');
local notifier = column1:AddSection('Notifier');
local playerMods = column1:AddSection('Player Mods');
local _visuals = column2:AddSection('Visuals');

local functions = {};

--[[
	reads the mode/ultimate charge from a players HUD bar.
	returns 0-100, or 0 if the gui doesnt exist
]]
local function GetModePercent(player: Player): number
	local playerGui = player:FindFirstChild('PlayerGui');
	if (not playerGui) then
		return 0;
	end;

	local hud = playerGui:FindFirstChild('HUD');
	if (not hud) then
        prettyPrint('ABA ESP: HUD not found for player', player.Name);
        return 0;
	end;

	local ultimate = (hud :: Frame):FindFirstChild('Ultimate');
	if (not ultimate) then
        prettyPrint('ABA ESP: Ultimate frame not found for player', player.Name);
		return 0;
	end;

	local bar = (ultimate :: Frame):FindFirstChild('Bar');

	return math.floor((bar :: Frame).Size.X.Scale * 100);
end;

function EntityESP:Plugin()
	local modeText: string = '';
	local modePercent: number? = nil;

	if (library.flags.showMode) then
		modePercent = GetModePercent(self._player);
		modeText = ` [Mode: {modePercent}%]`;
	end;

	return {
		text = modeText,
		playerName = self._playerName,
		modePercent = modePercent,
	};
end;

local NANAMI_CLICK_COOLDOWN: number = 0.15;
local nanamiTracking: { [Model]: boolean } = {};
local nanamiMaid = Maid.new();

local function WatchCutter(character: Model, cutter: GuiObject, goal: GuiObject, gui: BillboardGui): ()
	if (nanamiTracking[character]) then
		return;
	end;
	nanamiTracking[character] = true;

	local lastX: number? = nil;
	local connection: RBXScriptConnection? = nil;

	connection = RunService.RenderStepped:Connect(function(): ()
		if (not gui.Parent or not cutter.Parent or not goal.Parent) then
			if (connection) then
				(connection :: RBXScriptConnection):Disconnect();
			end;
			nanamiTracking[character] = nil;
			return;
		end;

		local cutterX: number = cutter.AbsolutePosition.X;
		local goalX: number = goal.AbsolutePosition.X;

		if (lastX and (lastX :: number) <= goalX and cutterX > goalX) then
			mouse1click();

			if (connection) then
				(connection :: RBXScriptConnection):Disconnect();
			end;

			task.delay(NANAMI_CLICK_COOLDOWN, function(): ()
				nanamiTracking[character] = nil;
			end);
			return;
		end;

		lastX = cutterX;
	end);

	-- track so we can kill it when toggled off
	local key: string = `cutterWatch_{tostring(character)}`;
	nanamiMaid[key] = connection;
end;

--[[
	tries to grab the cutter/goal from a gui that just appeared.
	if the children arent there yet we listen for them briefly
]]
local function TryAttach(character: Model, gui: BillboardGui): ()
	if (not library.flags.nanamiAutoBlackFlash) then
		return;
	end;

	local mainBar: Frame? = gui:FindFirstChild('MainBar') :: Frame?;
	if (not mainBar) then
		local child: Instance = gui:WaitForChild('MainBar', 1);
		if (not child) then
			return;
		end;
		mainBar = child :: Frame;
	end;

	local cutter: GuiObject? = (mainBar :: Frame):FindFirstChild('Cutter') :: GuiObject?;
	local goal: GuiObject? = (mainBar :: Frame):FindFirstChild('Goal') :: GuiObject?;

	if (not cutter) then
		local c: Instance = (mainBar :: Frame):WaitForChild('Cutter', 1);
		if (not c) then
			return;
		end;
		cutter = c :: GuiObject;
	end;

	if (not goal) then
		local g: Instance = (mainBar :: Frame):WaitForChild('Goal', 1);
		if (not g) then
			return;
		end;
		goal = g :: GuiObject;
	end;

	if (not gui.Parent) then
		return;
	end;

	WatchCutter(character, cutter :: GuiObject, goal :: GuiObject, gui);
end;

--[[
	hooks into a characters hrp so we catch the nanami gui the instant it appears.
	no polling so we dont miss instant pop/depop guis
]]
local function WatchCharacter(character: Model): ()
	local hrp: BasePart? = character:FindFirstChild('HumanoidRootPart') :: BasePart?;
	if (not hrp) then
		return;
	end;

	local existingGui: BillboardGui? = (hrp :: BasePart):FindFirstChild('NanamiCutGUI') :: BillboardGui?;
	if (existingGui) then
		task.spawn(TryAttach, character, existingGui :: BillboardGui);
	end;

	local conn: RBXScriptConnection = (hrp :: BasePart).ChildAdded:Connect(function(child: Instance): ()
		if (child.Name == 'NanamiCutGUI' and child:IsA('BillboardGui')) then
			task.spawn(TryAttach, character, child :: BillboardGui);
		end;
	end);

	local key: string = `charWatch_{tostring(character)}`;
	nanamiMaid[key] = conn;
end;

local function WatchLive(live: Folder): ()
	for _, character: Instance in live:GetChildren() do
		task.spawn(WatchCharacter, character :: Model);
	end;

	nanamiMaid.liveChildAdded = live.ChildAdded:Connect(function(child: Instance): ()
		task.spawn(WatchCharacter, child :: Model);
	end);
end;

function functions.nanamiAutoBlackFlash(toggle: boolean): ()
	if (not toggle) then
		nanamiMaid:DoCleaning();
		nanamiTracking = {};
		return;
	end;

	local live: Folder? = workspace:FindFirstChild('Live') :: Folder?;
	if (live) then
		WatchLive(live :: Folder);
	end;
end;

function functions.speedHack(toggle: boolean): ()
	if (not toggle) then
		maid.speedHack = nil;
		maid.speedHackBv = nil;
		return;
	end;

	maid.speedHack = RunService.Heartbeat:Connect(function(): ()
		local playerData = Utility:getPlayerData();
		local humanoid, rootPart = playerData.humanoid, playerData.primaryPart;
		if (not humanoid or not rootPart) then return end;

		if (library.flags.fly) then
			maid.speedHackBv = nil;
			return;
		end;

		maid.speedHackBv = maid.speedHackBv or Instance.new('BodyVelocity');
		maid.speedHackBv.MaxForce = Vector3.new(100000, 0, 100000);

		if (not CollectionService:HasTag(maid.speedHackBv, 'good')) then
			CollectionService:AddTag(maid.speedHackBv, 'good');
			CollectionService:AddTag(maid.speedHackBv, 'DONTDELETE');
		end;

		maid.speedHackBv.Parent = not library.flags.fly and rootPart or nil;
		maid.speedHackBv.Velocity = (humanoid.MoveDirection.Magnitude ~= 0 and humanoid.MoveDirection or gethiddenproperty(humanoid, 'WalkDirection')) * library.flags.speedHackValue;
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
		local rootPart, camera = playerData.rootPart, workspace.CurrentCamera;
		if (not rootPart or not camera) then return end;

		if (not CollectionService:HasTag(maid.flyBv, 'good')) then
			CollectionService:AddTag(maid.flyBv, 'good');
			CollectionService:AddTag(maid.flyBv, 'DONTDELETE');
		end;

		maid.flyBv.Parent = rootPart;
		maid.flyBv.Velocity = camera.CFrame:VectorToWorldSpace(ControlModule:GetMoveVector() * library.flags.flyHackValue);
	end);
end;

function functions.infiniteJump(toggle: boolean): ()
	if (not toggle) then return end;

	repeat
		local rootPart: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');
		if (rootPart and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
			(rootPart :: BasePart).Velocity = Vector3.new((rootPart :: BasePart).Velocity.X, library.flags.infiniteJumpHeight, (rootPart :: BasePart).Velocity.Z);
		end;
		task.wait(0.1);
	until not library.flags.infiniteJump;
end;

function functions.goToGround(): ()
	local params: RaycastParams = RaycastParams.new();
	params.FilterDescendantsInstances = {workspace.Mobs};
	params.FilterType = Enum.RaycastFilterType.Blacklist;

	local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');
	if (not hrp or not (hrp :: BasePart).Parent) then return end;

	local floor: RaycastResult? = workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -1000, 0), params);
	if (not floor or not (floor :: RaycastResult).Instance) then return end;

	(hrp :: BasePart).CFrame *= CFrame.new(0, -((hrp :: BasePart).Position.Y - (floor :: RaycastResult).Position.Y) + 3, 0);
	(hrp :: BasePart).Velocity *= Vector3.new(1, 0, 1);
end;

function functions.noClip(toggle: boolean): ()
	if (not toggle) then
		maid.noClip = nil;

		local humanoid = Utility:getPlayerData().humanoid;
		if (not humanoid) then return end;

		humanoid:ChangeState('Physics');
		task.wait();
		humanoid:ChangeState('RunningNoPhysics');
		return;
	end;

	maid.noClip = RunService.Stepped:Connect(function(): ()
		local myCharacterParts = Utility:getPlayerData().parts;
		local isKnocked = LocalPlayer.Character:FindFirstChild('Knocked') or LocalPlayer.Character:FindFirstChild('Ragdolled') or LocalPlayer.Character:FindFirstChild('ActuallyRagdolled');
		local disableNoClipWhenKnocked: boolean = library.flags.disableNoClipWhenKnocked;

		for _, v in myCharacterParts do
			if (disableNoClipWhenKnocked) then
				v.CanCollide = not not isKnocked;
			else
				v.CanCollide = false;
			end;
		end;
	end);
end;

function functions.clickDestroy(toggle: boolean): ()
	if (not toggle) then
		maid.clickDestroy = nil;
		return;
	end;

	maid.clickDestroy = UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean): ()
		if (input.UserInputType ~= Enum.UserInputType.MouseButton1 or gpe) then return end;

		local target = playerMouse.Target;
		if (not target or target:IsA('Terrain')) then return end;

		target:Destroy();
	end);
end;

function functions.serverHop(bypass: boolean?): ()
	if (bypass or library:ShowConfirm('Are you sure you want to switch server?')) then
		library:UpdateConfig();
		BlockUtils:BlockRandomUser();
		TeleportService:Teleport(89371625020632);
	end;
end;

function functions.respawn(bypass: boolean?): ()
	if (bypass or library:ShowConfirm('Are you sure you want to respawn?')) then
		LocalPlayer.Character.Humanoid.Health = 0;
	end;
end;

library.OnKeyPress:Connect(function(input, gpe): ()
	if (gpe or not library.options.attachToBack) then return end;

	local key = library.options.attachToBack.key;
	if (input.KeyCode.Name == key or input.UserInputType.Name == key) then
		local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');
		local closest, closestDistance = nil, math.huge;

		if (not hrp) then return end;

		repeat
			for _, entity in workspace.Mobs:GetChildren() do
				local rootPart: BasePart? = entity:FindFirstChild('HumanoidRootPart');
				if (not rootPart or rootPart == hrp) then continue end;

				local distance: number = ((rootPart :: BasePart).Position - (hrp :: BasePart).Position).Magnitude;

				if (distance < 300 and distance < closestDistance) then
					closest, closestDistance = rootPart, distance;
				end;
			end;

			task.wait();
		until closest or input.UserInputState == Enum.UserInputState.End;
		if (input.UserInputState == Enum.UserInputState.End) then return end;

		maid.attachToBack = RunService.Heartbeat:Connect(function(): ()
			local goalCF: CFrame = closest.CFrame * CFrame.new(0, library.flags.attachToBackHeight, library.flags.attachToBackSpace);

			local distance: number = (goalCF.Position - (hrp :: BasePart).Position).Magnitude;
			local tweenInfo: TweenInfo = TweenInfo.new(distance / 100, Enum.EasingStyle.Linear);

			local tween = TweenService:Create(hrp, tweenInfo, {
				CFrame = goalCF
			});

			tween:Play();

			maid.attachToBackTween = function(): ()
				tween:Cancel();
			end;
		end);
	end;
end);

library.OnKeyRelease:Connect(function(input): ()
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
	min = 16,
	max = 250,
	flag = 'Fly Hack Value',
	textpos = 2
});

localCheats:AddToggle({
	text = 'Speedhack',
	callback = functions.speedHack
});
localCheats:AddSlider({
	min = 16,
	max = 250,
	flag = 'Speed Hack Value',
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

localCheats:AddToggle({
	text = 'Click Destroy',
	tip = 'Everything you click on will be destroyed (client sided)',
	callback = functions.clickDestroy
});

localCheats:AddBind({ text = 'Go To Ground', callback = functions.goToGround, mode = 'hold', nomouse = true });

localCheats:AddDivider('Combat Tweaks');

localCheats:AddBind({
	text = 'Attach To Back',
	tip = 'This attaches to the nearest entities back based on settings',
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

localCheats:AddToggle({
	text = 'Nanami Auto Black Flash',
	tip = 'auto clicks when the cutter crosses the goal on nanamis cut gui',
	callback = functions.nanamiAutoBlackFlash
});

localCheats:AddDivider('Gameplay-Assist');

localCheats:AddButton({
	text = 'Server Hop',
	tip = 'Jumps to any other server, non region dependant',
	callback = functions.serverHop
});

localCheats:AddButton({
	text = 'Respawn',
	tip = 'Kills the character prompting it to respawn',
	callback = functions.respawn
});

function Utility:renderOverload(data)
	data.espSettings:AddToggle({
		text = 'Show Mode',
		tip = 'shows the mode/ultimate charge percentage on ESP text',
	});

	data.espSettings:AddToggle({
		text = 'Show Mode Bar',
		tip = 'renders a visual blue bar for mode charge next to the ESP box',
	});
end;
