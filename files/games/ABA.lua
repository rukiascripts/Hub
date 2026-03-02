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

local Players, RunService, UserInputService, HttpService, CollectionService, MemStorageService, Lighting, TweenService, VirtualInputManager, ReplicatedFirst, TeleportService, ReplicatedStorage, Stats = Services:Get(
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
	'ReplicatedStorage',
	'Stats'
);

if (game.PlaceId == 2008032602) then
     ToastNotif.new({
        text = 'Script will not run in matchmaking!',
        duration = 5
    });

    task.delay(0.005, function()
        library:Unload();
    end);
    return;
end;

local LocalPlayer: Player = Players.LocalPlayer;
local playerMouse = LocalPlayer:GetMouse();

local column1, column2 = unpack(library.columns);

local maid = Maid.new();

local localCheats = column1:AddSection('Local Cheats');
local autoParrySection = column2:AddSection('Auto Parry');
local automation = column2:AddSection('Automation');

local functions = {};

--[[
	reads the mode/ultimate charge from the Charge value under the player.
	returns 0-100 as a rounded percent
]]
local function GetModePercent(player: Player): number
	local charge: DoubleConstrainedValue = player:FindFirstChild('Charge') :: DoubleConstrainedValue;
	if (not charge) then
		return 0;
	end;

	local maxValue: number = (charge :: DoubleConstrainedValue).MaxValue;
	return math.floor((charge :: DoubleConstrainedValue).Value / maxValue * 100);
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

local ZOOM_BF_COOLDOWN: number = 0.15;
local zoomBfActive: boolean = false;
local zoomMaid = Maid.new();

function functions.zoomAutoBlackFlash(toggle: boolean): ()
	if (not toggle) then
		zoomMaid:DoCleaning();
		zoomBfActive = false;
		return;
	end;

	local camera: Camera = workspace.CurrentCamera;
	local defaultFov: number = 70;
	local lastFov: number = camera.FieldOfView;
	local zooming: boolean = false;
	local hitMin: boolean = false;

	zoomMaid.fovWatch = camera:GetPropertyChangedSignal('FieldOfView'):Connect(function(): ()
		local fov: number = camera.FieldOfView;

		-- detect zoom-in starting (FOV dropping significantly below default)
		if (not zooming and fov < defaultFov - 5) then
			zooming = true;
			hitMin = false;
		end;

		-- detect the FOV bottomed out and is now rising
		if (zooming and fov < lastFov) then
			hitMin = false;
		end;

		if (zooming and not hitMin and fov > lastFov) then
			hitMin = true;
		end;

		-- click when FOV is rising back and crosses the threshold
		if (zooming and hitMin and not zoomBfActive and fov >= defaultFov - 3) then
			zoomBfActive = true;
			zooming = false;
			hitMin = false;
			mouse1click();

			task.delay(ZOOM_BF_COOLDOWN, function(): ()
				zoomBfActive = false;
			end);
		end;

		-- reset if FOV returns to normal without triggering
		if (fov >= defaultFov - 1) then
			zooming = false;
			hitMin = false;
		end;

		lastFov = fov;
	end);
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
			task.wait(math.random() * 0.04);
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
		local child: Instance? = gui:WaitForChild('MainBar', 1);
		if (not child) then
			return;
		end;
		mainBar = child :: Frame;
	end;

	local cutter: GuiObject? = (mainBar :: Frame):FindFirstChild('Cutter') :: GuiObject?;
	local goal: GuiObject? = (mainBar :: Frame):FindFirstChild('Goal') :: GuiObject?;

	if (not cutter) then
		local c: Instance? = (mainBar :: Frame):WaitForChild('Cutter', 1);
		if (not c) then
			return;
		end;
		cutter = c :: GuiObject;
	end;

	if (not goal) then
		local g: Instance? = (mainBar :: Frame):WaitForChild('Goal', 1);
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
		local rootPart: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
		if (rootPart and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
			(rootPart :: any).Velocity = Vector3.new((rootPart :: any).Velocity.X, library.flags.infiniteJumpHeight, (rootPart :: any).Velocity.Z);
		end;
		task.wait(0.1);
	until not library.flags.infiniteJump;
end;

function functions.goToGround(): ()
	local params: RaycastParams = RaycastParams.new();
	params.FilterDescendantsInstances = {(workspace :: any).Mobs};
	params.FilterType = Enum.RaycastFilterType.Exclude;

	local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
	if (not hrp or not (hrp :: BasePart).Parent) then return end;

	local floor: RaycastResult? = workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -1000, 0), params);
	if (not floor or not (floor :: RaycastResult).Instance) then return end;

	(hrp :: BasePart).CFrame *= CFrame.new(0, -((hrp :: BasePart).Position.Y - (floor :: RaycastResult).Position.Y) + 3, 0);
	(hrp :: any).Velocity *= Vector3.new(1, 0, 1);
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
		local character = LocalPlayer.Character :: Model;
		local isKnocked = character:FindFirstChild('Knocked') or character:FindFirstChild('Ragdolled') or character:FindFirstChild('ActuallyRagdolled');
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



local lockedTarget: Player? = nil;

--[[
	finds the closest player to the mouse cursor within the lock on range.
	uses screen distance so it feels like mouse perspective
]]
local function FindClosestToMouse(): Player?
	local camera: Camera? = workspace.CurrentCamera;
	if (not camera) then
		return nil;
	end;

	local myCharacter: Model? = LocalPlayer.Character;
	local myHead: BasePart? = myCharacter and (myCharacter :: Model):FindFirstChild('Head') :: BasePart?;
	if (not myHead) then
		return nil;
	end;

	local mousePos: Vector2 = UserInputService:GetMouseLocation();
	local maxDistance: number = library.flags.lockOnMaxDistance;
	local closestPlayer: Player? = nil;
	local closestScreenDist: number = math.huge;

	for _, player: Player in Players:GetPlayers() do
		if (player == LocalPlayer) then continue end;
		if (library.flags.lockOnCheckTeam and Utility:isTeamMate(player)) then continue end;

		local character: Model? = player.Character;
		if (not character) then continue end;

		local humanoid: Humanoid? = (character :: Model):FindFirstChildOfClass('Humanoid');
		if (not humanoid or (humanoid :: Humanoid).Health <= 0) then continue end;

		local head: BasePart? = (character :: Model):FindFirstChild('Head') :: BasePart?;
		if (not head) then continue end;

		local worldDist: number = ((myHead :: BasePart).Position - (head :: BasePart).Position).Magnitude;
		if (worldDist > maxDistance) then continue end;

		local screenPos: Vector3, visible: boolean = (camera :: Camera):WorldToViewportPoint((head :: BasePart).Position);
		if (not visible) then continue end;

		local screenDist: number = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude;
		if (screenDist < closestScreenDist) then
			closestScreenDist = screenDist;
			closestPlayer = player;
		end;
	end;

	return closestPlayer;
end;

function functions.lockOn(toggle: boolean): ()
	if (not toggle) then
		maid.lockOn = nil;
		lockedTarget = nil;
		return;
	end;

	lockedTarget = FindClosestToMouse();
	if (not lockedTarget) then
		library.flags.lockOn = false;
		return;
	end;

	maid.lockOn = RunService.RenderStepped:Connect(function(): ()
		if (not lockedTarget) then
			maid.lockOn = nil;
			return;
		end;

		local character: Model? = (lockedTarget :: Player).Character;
		if (not character) then
			maid.lockOn = nil;
			lockedTarget = nil;
			return;
		end;

		local humanoid: Humanoid? = (character :: Model):FindFirstChildOfClass('Humanoid');
		if (not humanoid or (humanoid :: Humanoid).Health <= 0) then
			maid.lockOn = nil;
			lockedTarget = nil;
			return;
		end;

		local head: BasePart? = (character :: Model):FindFirstChild('Head') :: BasePart?;
		if (not head) then return end;

		local camera: Camera? = workspace.CurrentCamera;
		if (not camera) then return end;

		local aimPart: string = library.flags.lockOnAimPart or 'Head';
		local hitPos: Vector3 = (head :: BasePart).Position;

		if (aimPart == 'Torso') then
			hitPos -= Vector3.new(0, 1.5, 0);
		elseif (aimPart == 'Leg') then
			hitPos -= Vector3.new(0, 3, 0);
		end;

		local screenPos: Vector3, visible: boolean = (camera :: Camera):WorldToViewportPoint(hitPos);
		if (not visible) then return end;

		local mousePos: Vector2 = UserInputService:GetMouseLocation();
		local smoothness: number = library.flags.lockOnSmoothness or 1;
		local delta: Vector2 = (Vector2.new(screenPos.X, screenPos.Y) - mousePos) / smoothness;
		mousemoverel(delta.X, delta.Y);
	end);
end;

function functions.respawn(bypass: boolean?): ()
	if (bypass or library:ShowConfirm('Are you sure you want to respawn?')) then
		(LocalPlayer.Character :: any).Humanoid.Health = 0;
	end;
end;

local BLOCK_KEY: Enum.KeyCode = Enum.KeyCode.F;

-- m1 anim ids collected from anim logger, delay in seconds before blocking
local M1_ANIM_IDS: {[string]: number} = {
	['1461128166'] = 0.2,
	['1461128859'] = 0.2,
	['1461136273'] = 0.2,
	['1461136875'] = 0.2,
	['1461137417'] = 0.2,
	['1461145506'] = 0.2,
	['1461252313'] = 0.2,
};

local isAutoBlocking: boolean = false;
local autoParryEntityConns: {RBXScriptConnection} = {};

local function blockInput(): ()
	VirtualInputManager:SendKeyEvent(true, BLOCK_KEY, false, game);
end;

local function unblockInput(): ()
	VirtualInputManager:SendKeyEvent(false, BLOCK_KEY, false, game);
end;

--[[
	calculates the ping-adjusted wait time for blocking.
	subtracts a percentage of the player's ping from the raw delay
]]
local function calculateParryDelay(rawDelay: number): number
	if (library.flags.autoParryUseCustomDelay) then
		return rawDelay + library.flags.autoParryCustomDelay / 1000;
	end;

	local playerPing: number = Stats.PerformanceStats.Ping:GetValue() / 1000;
	return rawDelay - (playerPing * (library.flags.autoParryPingCompensation / 100));
end;

-- adds random jitter so timing doesnt look robotic
local function humanize(base: number, variance: number): number
	return base + (math.random() * 2 - 1) * variance;
end;

--[[
	does the actual block: waits the adjusted delay with some jitter,
	presses F, holds for a slightly randomized duration, then releases
]]
local function executeParry(rawDelay: number): ()
	if (isAutoBlocking) then return end;
	isAutoBlocking = true;

	local adjustedDelay: number = humanize(calculateParryDelay(rawDelay), 0.03);
	if (adjustedDelay > 0) then
		task.wait(adjustedDelay);
	end;

	blockInput();
	task.wait(humanize(library.flags.autoParryBlockDuration / 1000, 0.02));
	unblockInput();

	isAutoBlocking = false;
end;

--[[
	hooks a single character in workspace.Live, listens for animations
	and triggers parry when an M1 anim plays within range
]]
local function hookCharacterForParry(character: Model): ()
	if (not character or character == LocalPlayer.Character) then return end;

	local humanoid = character:FindFirstChildOfClass('Humanoid') or character:WaitForChild('Humanoid', 5) :: Humanoid;
	if (not humanoid) then return end;

	local player: Player? = Players:GetPlayerFromCharacter(character);

	local conn: RBXScriptConnection = (humanoid :: any).AnimationPlayed:Connect(function(animationTrack: AnimationTrack): ()
		if (isAutoBlocking) then return end;

		-- team check
		if (player and library.flags.autoParryCheckTeam and Utility:isTeamMate(player :: Player)) then return end;

		-- lock-on requirement check
		if (library.flags.autoParryRequireLockOn and (not lockedTarget or lockedTarget ~= player)) then return end;

		-- distance check
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart;
		local theirRoot = character:FindFirstChild('HumanoidRootPart') :: BasePart;
		if (not myRoot or not theirRoot) then return end;

		local distance: number = ((myRoot :: BasePart).Position - (theirRoot :: BasePart).Position).Magnitude;
		if (distance > library.flags.autoParryRadius) then return end;

		-- anim id check
		local animId: string = animationTrack.Animation and tostring(animationTrack.Animation.AnimationId):match('%d+') or '';
		local delay: number? = M1_ANIM_IDS[animId];
		if (not delay) then return end;

		task.spawn(executeParry, delay :: number);
	end);

	table.insert(autoParryEntityConns, conn);
end;

function functions.autoParry(toggle: boolean): ()
	if (not toggle) then
		maid.autoParry = nil;
		for _, conn in autoParryEntityConns do
			conn:Disconnect();
		end;
		table.clear(autoParryEntityConns);
		isAutoBlocking = false;
		return;
	end;

	local liveFolder = workspace:WaitForChild('Live');

	for _, character in liveFolder:GetChildren() do
		task.spawn(hookCharacterForParry, character :: any);
	end;

	maid.autoParry = liveFolder.ChildAdded:Connect(function(character: Instance): ()
		task.spawn(hookCharacterForParry, character :: any);
	end);
end;

local animLoggerWindow = TextLogger.new({
	title = 'Animation Logger',
	buttons = {'Copy Animation Id', 'Add To Ignore List', 'Delete Log', 'Clear All'}
});

animLoggerWindow.ignoreList = {};

local animLoggerMaid = Maid.new();

function functions.animLogger(toggle: boolean): ()
	animLoggerWindow:SetVisible(toggle);

	if (not toggle) then
		animLoggerMaid:DoCleaning();
		return;
	end;

	local liveFolder = workspace:WaitForChild('Live');

	local function onEntityAdded(entity: Instance): ()
		if (entity == LocalPlayer.Character) then return end;

		local rootPart = entity:WaitForChild('HumanoidRootPart', 10);
		if (not rootPart) then return end;

		local humanoid = entity:WaitForChild('Humanoid', 10);
		if (not humanoid) then return end;

		local entityMaid = Maid.new();

		entityMaid:GiveTask((entity :: any).Destroying:Connect(function(): ()
			entityMaid:DoCleaning();
		end));

		entityMaid:GiveTask((humanoid :: any).AnimationPlayed:Connect(function(animationTrack: AnimationTrack): ()
			local animId: string = animationTrack.Animation and tostring(animationTrack.Animation.AnimationId):match('%d+') or 'unknown';

			if (table.find(animLoggerWindow.ignoreList, animId)) then return end;

			local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart;
			if (myRoot and (myRoot :: BasePart).Position - (rootPart :: BasePart).Position).Magnitude > (library.flags.animLoggerMaxRange or 100) then
				return;
			end;

			animLoggerWindow:AddText({
				text = `Animation <font color='#2ecc71'>{animId}</font> played from <font color='#3498db'>{entity.Name}</font>`,
				animationId = animId,
			});
		end));

		animLoggerMaid:GiveTask(function(): ()
			entityMaid:DoCleaning();
		end);
	end;

	animLoggerMaid:GiveTask(liveFolder.ChildAdded:Connect(onEntityAdded));

	for _, entity in liveFolder:GetChildren() do
		task.spawn(onEntityAdded, entity);
	end;

	animLoggerMaid:GiveTask(animLoggerWindow.OnClick:Connect(function(actionName, context)
		if (actionName == 'Add To Ignore List' and not table.find(animLoggerWindow.ignoreList, context.animationId)) then
			table.insert(animLoggerWindow.ignoreList, context.animationId);
		elseif (actionName == 'Delete Log') then
			context:Destroy();
		elseif (actionName == 'Copy Animation Id') then
			setclipboard(context.animationId);
		elseif (actionName == 'Clear All') then
			for _, v in animLoggerWindow.allLogs do
				v.label:Destroy();
			end;
			table.clear(animLoggerWindow.allLogs);
		end;
	end));
end;

library.OnKeyPress:Connect(function(input, gpe): ()
	if (gpe or not library.options.attachToBack) then return end;

	local key = library.options.attachToBack.key;
	if (input.KeyCode.Name == key or input.UserInputType.Name == key) then
		local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
		local closest, closestDistance = nil, math.huge;

		if (not hrp) then return end;

		repeat
			for _, entity in (workspace :: any).Live:GetChildren() do
				local rootPart: BasePart? = entity:FindFirstChild('HumanoidRootPart') :: BasePart?;
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

localCheats:AddBind({
	text = 'Lock On',
	flag = 'Lock On Bind',
	tip = 'toggles lock on to the closest player to your mouse',
	mode = 'toggle',
	nomouse = true,
	callback = functions.lockOn
});

localCheats:AddList({
	text = 'Lock On Aim Part',
	values = {'Head', 'Torso'},
	value = 'Head'
});

localCheats:AddToggle({
	text = 'Lock On Check Team',
	state = true
});

localCheats:AddSlider({
	text = 'Lock On Max Distance',
	value = 200,
	min = 10,
	max = 1000,
	textpos = 2
});

localCheats:AddSlider({
	text = 'Lock On Smoothness',
	value = 1,
	min = 1,
	max = 20,
	textpos = 2
});

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


localCheats:AddDivider('Gameplay-Assist');

localCheats:AddButton({
	text = 'Respawn',
	tip = 'Kills the character prompting it to respawn',
	callback = functions.respawn
});

autoParrySection:AddToggle({
	text = 'Auto Parry',
	tip = 'blocks when nearby enemies play M1 animations',
	callback = functions.autoParry
});

autoParrySection:AddToggle({
	text = 'Auto Parry Check Team',
	tip = 'skip teammates when auto parrying',
	state = true
});

autoParrySection:AddToggle({
	text = 'Auto Parry Require Lock On',
	tip = 'only parry the player you have locked on to',
	state = false
});

autoParrySection:AddSlider({
	text = 'Auto Parry Radius',
	tip = 'max distance to auto parry',
	value = 15,
	min = 5,
	max = 50,
	textpos = 2
});

autoParrySection:AddSlider({
	text = 'Auto Parry Block Duration',
	tip = 'how long to hold block in ms',
	value = 150,
	min = 50,
	max = 500,
	textpos = 2
});

autoParrySection:AddSlider({
	text = 'Auto Parry Ping Compensation',
	tip = 'percentage of ping to subtract from delay',
	value = 50,
	min = 0,
	max = 100,
	textpos = 2
});

autoParrySection:AddToggle({
	text = 'Auto Parry Use Custom Delay',
	tip = 'use a fixed offset instead of ping-based compensation',
	state = false
});

autoParrySection:AddSlider({
	text = 'Auto Parry Custom Delay',
	tip = 'fixed delay offset in ms (added to raw timing)',
	value = 0,
	min = -200,
	max = 200,
	textpos = 2
});

autoParrySection:AddToggle({
	text = 'Animation Logger',
	tip = 'opens a gui logger with copy/ignore buttons for finding M1 anim IDs',
	callback = functions.animLogger
});

autoParrySection:AddSlider({
	text = 'Anim Logger Max Range',
	tip = 'only log animations from entities within this distance',
	value = 100,
	min = 10,
	max = 500,
	textpos = 2
});

automation:AddToggle({
	text = 'Nanami Auto Black Flash',
	tip = 'auto clicks when the cutter crosses the goal on nanamis cut gui',
	callback = functions.nanamiAutoBlackFlash
});

automation:AddToggle({
	text = 'Auto Zoom QTE',
	tip = 'auto clicks when the camera zoom-out returns to normal FOV',
	callback = functions.zoomAutoBlackFlash
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

	-- deidara mines get parented to workspace.Thrown as a unionoperation called 'Ball'
	makeESP({
		sectionName = 'Deidara Mines',
		type = 'childAdded',
		args = {workspace:WaitForChild('Thrown')},
		callback = function(obj: Instance, espConstructor)
			if (not obj:IsA('UnionOperation') or obj.Name ~= 'Ball') then return end;

			local espObj = espConstructor.new(obj :: BasePart, 'Deidara Mine');

            task.spawn(function()
                while (obj.Transparency == 0) do
                    task.wait(0.1);
                end;
                obj.Transparency = 0.5;
            end);

			local connection: RBXScriptConnection;
			connection = obj:GetPropertyChangedSignal('Parent'):Connect(function()
				if (not obj.Parent) then
					espObj:Destroy();
					connection:Disconnect();
				end;
			end);
		end,
	});

	-- raiden claymores get parented to workspace.ClearEachMatch as meshparts
	makeESP({
		sectionName = 'Raiden Claymores',
		type = 'childAdded',
		args = {workspace:WaitForChild('ClearEachMatch')},
		callback = function(obj: Instance, espConstructor)
			if (not obj:IsA('MeshPart')) then return end;

			local espObj = espConstructor.new(obj :: BasePart, 'Claymore');
            
            task.spawn(function()
                while (obj.Transparency == 0) do
                    task.wait(0.1);
                end;
                obj.Transparency = 0.5;
            end);

			local connection: RBXScriptConnection;
			connection = obj:GetPropertyChangedSignal('Parent'):Connect(function()
				if (not obj.Parent) then
					espObj:Destroy();
					connection:Disconnect();
				end;
			end);
		end,
	});
end;
