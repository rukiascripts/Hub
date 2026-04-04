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

Players = cloneref(Players);
RunService = cloneref(RunService);
UserInputService = cloneref(UserInputService);
ReplicatedStorage = cloneref(ReplicatedStorage);
TweenService = cloneref(TweenService);
CollectionService = cloneref(CollectionService);
TeleportService = cloneref(TeleportService);
Lighting = cloneref(Lighting);

local BLOCKED_PLACES: {[number]: string} = {
	[12360882630] = 'Script will not run in duels lobby!',
};

local blockedMessage: string? = BLOCKED_PLACES[game.PlaceId];
if (blockedMessage) then
	ToastNotif.new({ text = blockedMessage :: string, duration = 5 });
	task.delay(0.005, function(): ()
		library:Unload();
	end);
	return;
end;

local ATTACH_MAX_RANGE: number = 700;

local LocalPlayer: Player = Players.LocalPlayer;
local playerMouse = LocalPlayer:GetMouse();

local column1, column2 = unpack(library.columns);

local maid = Maid.new();

local localCheats = column1:AddSection('Local Cheats');
local autoParrySection = column2:AddSection('Auto Parry');
local gameplayAssist = column2:AddSection('Gameplay-Assist');

local functions = {};

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
	until (not library.flags.infiniteJump);
end;

function functions.goToGround(): ()
	local params: RaycastParams = RaycastParams.new();
	params.FilterDescendantsInstances = {};
	params.FilterType = Enum.RaycastFilterType.Exclude;

	local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
	if (not hrp or not (hrp :: BasePart).Parent) then return end;

	local floor: RaycastResult? = workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -1000, 0), params);
	if (not floor or not (floor :: RaycastResult).Instance) then return end;

	(hrp :: BasePart).CFrame *= CFrame.new(0, -((hrp :: BasePart).Position.Y - (floor :: RaycastResult).Position.Y) + 3, 0);
	(hrp :: any).Velocity *= Vector3.new(1, 0, 1);
end;

--[[
	teleports below the map floor. noclip should be on or you'll
	just get pushed back up
]]
function functions.goUnderground(): ()
	local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
	if (not hrp or not (hrp :: BasePart).Parent) then return end;

	local params: RaycastParams = RaycastParams.new();
	params.FilterType = Enum.RaycastFilterType.Exclude;
	params.FilterDescendantsInstances = {LocalPlayer.Character :: any};

	local floor: RaycastResult? = workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -1000, 0), params);
	local depth: number = library.flags.undergroundDepth;

	if (floor) then
		(hrp :: BasePart).CFrame = CFrame.new((hrp :: BasePart).Position.X, (floor :: RaycastResult).Position.Y - depth, (hrp :: BasePart).Position.Z);
	else
		(hrp :: BasePart).CFrame *= CFrame.new(0, -depth, 0);
	end;

	(hrp :: any).Velocity = Vector3.zero;
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
			v.CanCollide = disableNoClipWhenKnocked and isKnocked ~= nil;
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

--[[
	touch fling - saves your position, tps to target, spikes velocity
	to fling them, then returns to original spot when target is lost
]]
function functions.fling(toggle: boolean): ()
	if (not toggle) then
		maid.fling = nil;
		return;
	end;

	local function getClosestTarget(origin: Vector3): (BasePart?, Player?)
		local maxRange: number = library.flags.flingRange;
		local closest: BasePart? = nil;
		local closestPlayer: Player? = nil;
		local closestDist: number = math.huge;

		for _, player: Player in Players:GetPlayers() do
			if (player == LocalPlayer) then continue end;
			if (library.flags.flingCheckTeam and Utility:isTeamMate(player)) then continue end;

			local character: Model? = player.Character;
			if (not character) then continue end;

			local humanoid: Humanoid? = (character :: Model):FindFirstChildOfClass('Humanoid');
			if (not humanoid or (humanoid :: Humanoid).Health <= 0) then continue end;

			local rootPart: BasePart? = (character :: Model):FindFirstChild('HumanoidRootPart') :: BasePart?;
			if (not rootPart) then continue end;

			local dist: number = (origin - (rootPart :: BasePart).Position).Magnitude;
			if (dist < maxRange and dist < closestDist) then
				closest = rootPart;
				closestPlayer = player;
				closestDist = dist;
			end;
		end;

		return closest, closestPlayer;
	end;

	local wobble: number = 0.1;
	local savedCF: CFrame? = nil;
	local currentTarget: Player? = nil;

	maid.fling = RunService.Heartbeat:Connect(function(): ()
		local character: Model? = LocalPlayer.Character;
		local hrp: BasePart? = character and (character :: Model):FindFirstChild('HumanoidRootPart') :: BasePart?;
		if (not hrp) then return end;

		-- check if current target is still valid (alive and has character)
		local targetLost: boolean = false;
		if (currentTarget) then
			local tChar: Model? = (currentTarget :: Player).Character;
			local tHum: Humanoid? = tChar and (tChar :: Model):FindFirstChildOfClass('Humanoid');
			if (not tChar or not tHum or (tHum :: Humanoid).Health <= 0) then
				targetLost = true;
			end;
		end;

		-- target died or despawned, tp back to where we were
		if (targetLost and savedCF) then
			(hrp :: BasePart).CFrame = savedCF :: CFrame;
			(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero;
			savedCF = nil;
			currentTarget = nil;
			return;
		end;

		-- use saved origin for range check so we dont drift
		local searchOrigin: Vector3 = savedCF and (savedCF :: CFrame).Position or (hrp :: BasePart).Position;
		local targetRoot: BasePart?, targetPlayer: Player? = getClosestTarget(searchOrigin);

		-- no target, just chill at our spot
		if (not targetRoot) then
			if (savedCF) then
				(hrp :: BasePart).CFrame = savedCF :: CFrame;
				(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero;
				savedCF = nil;
				currentTarget = nil;
			end;
			return;
		end;

		-- save position before first tp
		if (not savedCF) then
			savedCF = (hrp :: BasePart).CFrame;
		end;

		currentTarget = targetPlayer;

		-- tp onto target
		if (library.flags.flingTeleport) then
			(hrp :: BasePart).CFrame = (targetRoot :: BasePart).CFrame;
		end;

		-- spike velocity on every part + high density for max collision force
		local frameCF: CFrame = (hrp :: BasePart).CFrame;
		local power: number = library.flags.flingPower;

		-- fling downward to avoid sky barrier, push them under the map
		local flingDir: Vector3 = Vector3.new(1, -1, 1).Unit;
		if (targetRoot) then
			local rawDir: Vector3 = ((targetRoot :: BasePart).Position - (hrp :: BasePart).Position);
			if (rawDir.Magnitude > 0.1) then
				flingDir = (rawDir.Unit + Vector3.new(0, -1, 0)).Unit;
			end;
		end;

		local powerVec: Vector3 = flingDir * power;
		local spinVec: Vector3 = Vector3.new(power, power, power);
		local heavyPhysics: PhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5);

		local parts: {BasePart} = {};
		for _, part: Instance in (character :: Model):GetDescendants() do
			if (not part:IsA('BasePart')) then continue end;
			table.insert(parts, part :: BasePart);
			part.CustomPhysicalProperties = heavyPhysics;
			part.CanCollide = true;
		end;

		for _ = 1, 4 do
			for _, part: BasePart in parts do
				(part :: any).Velocity = powerVec;
				(part :: any).RotVelocity = spinVec;
			end;
			RunService.RenderStepped:Wait();
			(hrp :: BasePart).CFrame = frameCF;
		end;

		for _, part: BasePart in parts do
			(part :: any).Velocity = Vector3.new(0, wobble, 0);
			(part :: any).RotVelocity = Vector3.zero;
		end;
		wobble = -wobble;
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

local LOCK_ON_BIND_NAME: string = '__lockOn';

function functions.lockOn(toggle: boolean): ()
	if (not toggle) then
		pcall(RunService.UnbindFromRenderStep, RunService, LOCK_ON_BIND_NAME);
		lockedTarget = nil;
		return;
	end;

	lockedTarget = FindClosestToMouse();
	if (not lockedTarget) then
		library.flags.lockOn = false;
		return;
	end;

	RunService:BindToRenderStep(LOCK_ON_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(): ()
		if (not lockedTarget) then
			pcall(RunService.UnbindFromRenderStep, RunService, LOCK_ON_BIND_NAME);
			return;
		end;

		local character: Model? = (lockedTarget :: Player).Character;
		if (not character) then
			pcall(RunService.UnbindFromRenderStep, RunService, LOCK_ON_BIND_NAME);
			lockedTarget = nil;
			return;
		end;

		local humanoid: Humanoid? = (character :: Model):FindFirstChildOfClass('Humanoid');
		if (not humanoid or (humanoid :: Humanoid).Health <= 0) then
			pcall(RunService.UnbindFromRenderStep, RunService, LOCK_ON_BIND_NAME);
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
		elseif (aimPart == 'Left Arm' or aimPart == 'Right Arm') then
			local armPart: BasePart? = (character :: Model):FindFirstChild(aimPart) :: BasePart?;
			if (armPart) then
				hitPos = (armPart :: BasePart).Position;
			end;
		end;

		local camPos: Vector3 = (camera :: Camera).CFrame.Position;
		local goalCF: CFrame = CFrame.new(camPos, hitPos);
		local speed: number = library.flags.lockOnSpeed or 100;
		(camera :: Camera).CFrame = (camera :: Camera).CFrame:Lerp(goalCF, speed / 100);
	end);
end;

function functions.respawn(bypass: boolean?): ()
	if (bypass or library:ShowConfirm('Are you sure you want to respawn?')) then
		(LocalPlayer.Character :: any).Humanoid.Health = 0;
	end;
end;

local oldNamecall: ((...any) -> ...any)? = nil;

function functions.antiKick(toggle: boolean): ()
	if (not toggle) then
		if (oldNamecall) then
			local mt: any = getrawmetatable(game);
			setreadonly(mt, false);
			mt.__namecall = oldNamecall;
			setreadonly(mt, true);
			oldNamecall = nil;
		end;
		return;
	end;

	local mt: any = getrawmetatable(game);
	setreadonly(mt, false);

	oldNamecall = mt.__namecall;

	mt.__namecall = newcclosure(function(self: any, ...: any): ...any
		if (not checkcaller() and getnamecallmethod() == 'Kick') then
			return;
		end;
		return (oldNamecall :: any)(self, ...);
	end);

	setreadonly(mt, true);
end;

local BLOCK_KEY: Enum.KeyCode = Enum.KeyCode.F;

local WINDUP_ANIM_IDS: {[string]: boolean} = {
	['10479335397'] = true; -- windup w/ fist
	['13380255751'] = true; -- windup w/ sword
};

-- m1 anim ids collected from anim logger, delay in seconds before blocking
local M1_ANIM_IDS: {[string]: number} = {

    -- saitama m1 1-4
    ['10469493270'] = 0,
    ['10469630950'] = 0;
    ['10469639222'] = 0;
    ['10469643643'] = 0;

    -- garou m1 1-4

    ['13532562418'] = 0;
    ['13532600125'] = 0;
    ['13532604085'] = 0;
    ['13294471966'] = 0;

    -- genos m1 1-4

    ['13491635433'] = 0;
    ['13296577783'] = 0;
    ['13295919399'] = 0;
    ['13295936866'] = 0;

    -- sonic m1 1-4
    ['13370310513'] = 0;
    ['13390230973'] = 0;
    ['13378751717'] = 0;
    ['13378708199'] = 0;

    -- metal bat m1 1-4
    ['14004222985'] = 0;
    ['13997092940'] = 0;
    ['14001963401'] = 0;
    ['14136436157'] = 0;

    -- atomic samurai m1 1-4
    ['15259161390'] = 0;
    ['15240216931'] = 0;
    ['15240176873'] = 0;
    ['15162694192'] = 0;

    -- tatsumaki m1 1-4
    ['16515503507'] = 0;
    ['16515520431'] = 0;
    ['16515448089'] = 0;
    ['16552234590'] = 0;

    -- martial artist m1 1-4
    ['17889458563'] = 0;
    ['17889461810'] = 0;
    ['17889471098'] = 0;
    ['17889290569'] = 0;

    -- downslam & uppercuts
    ['10470104242'] = 0; -- fist/sword downslam
    ['10503381238'] = 0; -- fist uppercut
    
    ['13379003796'] = 0; -- katana/bat uppercut
    

	-- front dash (windup into dash)
	['10479335397'] = 0; -- windup w/ fist
	['13380255751'] = 0; -- windup w/ sword
};

local isAutoBlocking: boolean = false;
local isVirtualPress: boolean = false;
local isManuallyBlocking: boolean = false;
local autoParryMaid = Maid.new();

maid.manualBlockDown = UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean): ()
	if (gpe) then return end;
	if (input.KeyCode == BLOCK_KEY and not isVirtualPress) then
		isManuallyBlocking = true;
	end;
end);

maid.manualBlockUp = UserInputService.InputEnded:Connect(function(input: InputObject): ()
	if (input.KeyCode == BLOCK_KEY and not isVirtualPress) then
		isManuallyBlocking = false;
	end;
end);

local function blockInput(): ()
	isVirtualPress = true;
	VirtualInputManager:SendKeyEvent(true, BLOCK_KEY, false, game);
	isVirtualPress = false;
end;

local function unblockInput(): ()
	isVirtualPress = true;
	VirtualInputManager:SendKeyEvent(false, BLOCK_KEY, false, game);
	isVirtualPress = false;
end;

--[[
	calculates the ping-adjusted wait time for blocking.
	subtracts a percentage of the player's ping from the raw delay
]]
local function calculateParryDelay(rawDelay: number): number
	if (library.flags.autoParryCustomDelay) then
		return rawDelay + library.flags.autoParryCustomDelayValue / 1000;
	end;

	local playerPing: number = Stats.PerformanceStats.Ping:GetValue() / 1000;
	return rawDelay - (playerPing * (library.flags.pingCompensation / 100));
end;


local function isSneaking(): boolean
	local character: Model? = LocalPlayer.Character;
	if (not character) then
		return false;
	end;

	return character:FindFirstChild('SneakAttack') ~= nil;
end;

local function executeParry(rawDelay: number, isWindup: boolean?): ()
	if (isAutoBlocking or isSneaking()) then
		return;
	end;

	isAutoBlocking = true;

	local adjustedDelay: number = calculateParryDelay(rawDelay);
	if (adjustedDelay > 0) then
		task.wait(adjustedDelay);

		-- re-check after waiting
		if (isSneaking()) then
			isAutoBlocking = false;
			return;
		end;
	end;

	blockInput();

	task.spawn(function(): ()
		local duration: number = library.flags.blockDuration;
		if (isWindup) then
			duration *= (library.flags.windupBlockMultiplier / 100);
		end;

		task.wait(duration / 1000);

		if (not isManuallyBlocking or library.flags.autoParryForceUnblock) then
			unblockInput();
		end;

		isAutoBlocking = false;
	end);
end;

--[[
	hooks a single character in workspace.Live, listens for animations
	and triggers parry when an M1 anim plays within range
]]
local function hookCharacterForParry(character: Model): ()
	if (not character or character == LocalPlayer.Character) then return end;

	local humanoid: Humanoid? = (character:FindFirstChildOfClass('Humanoid') or character:WaitForChild('Humanoid', 5)) :: any;
	if (not humanoid) then return end;

	local player: Player? = Players:GetPlayerFromCharacter(character);
	local entityMaid = Maid.new();

	entityMaid:GiveTask((character :: any).Destroying:Connect(function(): ()
		entityMaid:DoCleaning();
	end));

	entityMaid:GiveTask((humanoid :: any).AnimationPlayed:Connect(function(animationTrack: AnimationTrack): ()
		if (isAutoBlocking) then return end;

		-- team check
		if (player and library.flags.autoParryCheckTeam and Utility:isTeamMate(player :: Player)) then return end;

		-- lock-on requirement check
		if (library.flags.autoParryLockOn and (not lockedTarget or lockedTarget ~= player)) then return end;

		-- anim id check (before distance so we know if windup)
		local animId: string = animationTrack.Animation and tostring(animationTrack.Animation.AnimationId):match('%d+') or '';
		local delay: number? = M1_ANIM_IDS[animId];
		if (not delay) then return end;

		local isWindup: boolean? = WINDUP_ANIM_IDS[animId];

		-- distance check
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart;
		local theirRoot = character:FindFirstChild('HumanoidRootPart') :: BasePart;
		if (not myRoot or not theirRoot) then return end;

		local maxRadius: number = isWindup and library.flags.windupRadius or library.flags.radius;
		local distance: number = ((myRoot :: BasePart).Position - (theirRoot :: BasePart).Position).Magnitude;
		if (distance > maxRadius) then return end;

		executeParry(delay :: number, isWindup);
	end));

	autoParryMaid:GiveTask(function(): ()
		entityMaid:DoCleaning();
	end);
end;

local function hookStandForParry(stand: Model): ()
	-- skip own stand
	if (stand.Name == LocalPlayer.Name) then return end;

	local humanoid: Humanoid? = (stand:FindFirstChildOfClass('Humanoid') or stand:WaitForChild('Humanoid', 5)) :: any;
	if (not humanoid) then return end;

	local rootPart: BasePart? = stand:FindFirstChild('HumanoidRootPart') :: BasePart?;
	if (not rootPart) then return end;

	local entityMaid = Maid.new();

	entityMaid:GiveTask((stand :: any).Destroying:Connect(function(): ()
		entityMaid:DoCleaning();
	end));

	local standOwner: Player? = Players:FindFirstChild(stand.Name) :: any;

	entityMaid:GiveTask((humanoid :: any).AnimationPlayed:Connect(function(animationTrack: AnimationTrack): ()
		if (isAutoBlocking) then return end;

		-- team check
		if (standOwner and library.flags.autoParryCheckTeam and Utility:isTeamMate(standOwner :: Player)) then return end;

		-- lock-on requirement check (match stand name to locked player name)
		if (library.flags.autoParryLockOn and (not lockedTarget or (lockedTarget :: Player).Name ~= stand.Name)) then return end;

		-- anim id check (before distance so we know if windup)
		local animId: string = animationTrack.Animation and tostring(animationTrack.Animation.AnimationId):match('%d+') or '';
		local delay: number? = M1_ANIM_IDS[animId];
		if (not delay) then return end;

		local isWindup: boolean? = WINDUP_ANIM_IDS[animId];

		-- distance check
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart;
		if (not myRoot) then return end;

		local maxRadius: number = isWindup and library.flags.windupRadius or library.flags.radius;
		local distance: number = ((myRoot :: BasePart).Position - (rootPart :: BasePart).Position).Magnitude;
		if (distance > maxRadius) then return end;

		executeParry(delay :: number, isWindup);
	end));

	autoParryMaid:GiveTask(function(): ()
		entityMaid:DoCleaning();
	end);
end;

function functions.autoParry(toggle: boolean): ()
	if (not toggle) then
		maid.autoParry = nil;
		maid.autoParryStands = nil;
		autoParryMaid:DoCleaning();
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

	local standsFolder = workspace:FindFirstChild('Stands');
	if (standsFolder) then
		for _, stand in standsFolder:GetChildren() do
			task.spawn(hookStandForParry, stand :: any);
		end;

		maid.autoParryStands = standsFolder.ChildAdded:Connect(function(stand: Instance): ()
			task.spawn(hookStandForParry, stand :: any);
		end);
	end;
end;

local animLoggerWindow = TextLogger.new({
	title = 'Animation Logger',
	buttons = {'Copy Animation Id', 'Add To Ignore List', 'Delete Log', 'Clear All'}
});

animLoggerWindow.ignoreList = {};

local animLoggerMaid = Maid.new();

local function hookAnimLogger(entity: Instance, rootPart: Instance, humanoid: Instance, label: string): ()
	local entityMaid = Maid.new();

	entityMaid:GiveTask((entity :: any).Destroying:Connect(function(): ()
		entityMaid:DoCleaning();
	end));

	entityMaid:GiveTask((humanoid :: any).AnimationPlayed:Connect(function(animationTrack: AnimationTrack): ()
		local animId: string = animationTrack.Animation and tostring(animationTrack.Animation.AnimationId):match('%d+') or 'unknown';

		if (animLoggerWindow.ignoreList[animId]) then return end;

		local myRoot: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart;
		if (myRoot and ((myRoot :: BasePart).Position - (rootPart :: BasePart).Position).Magnitude > (library.flags.animLoggerMaxRange or 100)) then
			return;
		end;

		animLoggerWindow:AddText({
			text = `Animation <font color='#2ecc71'>{animId}</font> played from {label}`,
			animationId = animId,
		});
	end));

	animLoggerMaid:GiveTask(function(): ()
		entityMaid:DoCleaning();
	end);
end;

function functions.animLogger(toggle: boolean): ()
	animLoggerWindow:SetVisible(toggle);

	if (not toggle) then
		animLoggerMaid:DoCleaning();
		return;
	end;

	local liveFolder = workspace:WaitForChild('Live');

	local function onEntityAdded(entity: Instance): ()
		--if (entity == LocalPlayer.Character) then return end;

		local rootPart: Instance? = entity:WaitForChild('HumanoidRootPart', 10);
		if (not rootPart) then return end;

		local humanoid: Instance? = entity:WaitForChild('Humanoid', 10);
		if (not humanoid) then return end;

		hookAnimLogger(entity, rootPart :: Instance, humanoid :: Instance, `<font color='#3498db'>{entity.Name}</font>`);
	end;

	animLoggerMaid:GiveTask(liveFolder.ChildAdded:Connect(onEntityAdded));

	for _, entity in liveFolder:GetChildren() do
		task.spawn(onEntityAdded, entity);
	end;
end;

animLoggerWindow.OnClick:Connect(function(actionName: string, context: any): ()

	if (actionName == 'Add To Ignore List' and not animLoggerWindow.ignoreList[context.animationId]) then
		animLoggerWindow.ignoreList[context.animationId] = true;
	elseif (actionName == 'Delete Log') then
		context:Destroy();
	elseif (actionName == 'Copy Animation Id') then
		setclipboard(context.animationId);
	elseif (actionName == 'Clear All') then
		for _, v in animLoggerWindow.logs do
			v.label:Destroy();
		end;
		table.clear(animLoggerWindow.logs);
		table.clear(animLoggerWindow.allLogs);
	end;
end);

library.OnKeyPress:Connect(function(input: InputObject, gpe: boolean): ()
	if (gpe or not library.options.attachToBack) then return end;

	local key = library.options.attachToBack.key;
	if (input.KeyCode.Name == key or input.UserInputType.Name == key) then
		local hrp: BasePart? = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart') :: BasePart?;
		local closest: BasePart?, closestDistance: number = nil, math.huge;

		if (not hrp) then return end;

		repeat
			for _, entity in (workspace :: any).Live:GetChildren() do
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

		maid.attachToBack = RunService.Heartbeat:Connect(function(): ()
			local goalCF: CFrame = (closest :: BasePart).CFrame * CFrame.new(0, library.flags.attachToBackHeight, library.flags.attachToBackSpace);
			(hrp :: BasePart).CFrame = goalCF;
		end);
	end;
end);

library.OnKeyRelease:Connect(function(input: InputObject): ()
	if (not library.options.attachToBack) then return end;
	local key = library.options.attachToBack.key;

	if (input.KeyCode.Name == key or input.UserInputType.Name == key) then
		maid.attachToBack = nil;
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

localCheats:AddBind({ text = 'Go Underground', tip = 'teleports below the map, use with noclip', callback = functions.goUnderground, nomouse = true });
localCheats:AddSlider({
	text = 'Underground Depth',
	tip = 'how far below the floor to teleport',
	value = 50,
	min = 10,
	max = 300,
	textpos = 2
});

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
	values = {'Head', 'Torso', 'Left Arm', 'Right Arm'},
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
	text = 'Lock On Speed',
	tip = '100 = instant snap, lower = smoother tracking',
	value = 100,
	min = 5,
	max = 100,
	textpos = 2
});

localCheats:AddDivider('Combat Tweaks');

localCheats:AddToggle({
	text = 'Fling',
	tip = 'spins your character into nearby players to fling them via physics',
	callback = functions.fling
});

localCheats:AddToggle({
	text = 'Fling Teleport',
	tip = 'teleport to the nearest player while flinging',
	state = true
});

localCheats:AddToggle({
	text = 'Fling Check Team',
	tip = 'skip teammates when selecting fling target',
	state = true
});

localCheats:AddSlider({
	text = 'Fling Power',
	tip = 'velocity multiplier, higher = stronger fling',
	value = 50000,
	min = 5000,
	max = 200000,
	textpos = 2
});

localCheats:AddSlider({
	text = 'Fling Range',
	tip = 'max distance to find a target',
	value = 50,
	min = 10,
	max = 500,
	textpos = 2
});

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

gameplayAssist:AddToggle({
	text = 'Anti Kick',
	tip = 'blocks server-side kick calls via namecall hook',
	callback = functions.antiKick
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
	text = 'Auto Parry Lock On',
	tip = 'only parry the player you have locked on to',
	state = false
});

autoParrySection:AddSlider({
	text = 'Radius',
	tip = 'max distance to auto parry',
	value = 15,
	min = 5,
	max = 50,
	textpos = 2
});

autoParrySection:AddSlider({
	text = 'Windup Radius',
	tip = 'max distance to detect windup animations (dash etc)',
	value = 30,
	min = 5,
	max = 100,
	textpos = 2
});

autoParrySection:AddSlider({
	text = 'Block Duration',
	tip = 'how long to hold block in ms',
	value = 150,
	min = 50,
	max = 500,
	textpos = 2
});

autoParrySection:AddSlider({
	text = 'Windup Block Multiplier',
	tip = 'block duration multiplier for windup anims (100 = normal, 150 = 1.5x longer)',
	value = 150,
	min = 50,
	max = 300,
	textpos = 2
});

autoParrySection:AddSlider({
	text = 'Ping Compensation',
	tip = 'percentage of ping to subtract from delay',
	value = 100,
	min = 0,
	max = 100,
	textpos = 2
});

autoParrySection:AddToggle({
	text = 'Auto Parry Force Unblock',
	tip = 'unblock after parry even if you are holding F',
	state = true
});

autoParrySection:AddToggle({
	text = 'Auto Parry Custom Delay',
	tip = 'use a fixed offset instead of ping-based compensation',
	state = false
});

autoParrySection:AddSlider({
	text = 'Auto Parry Custom Delay',
	flag = 'Auto Parry Custom Delay Value',
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
