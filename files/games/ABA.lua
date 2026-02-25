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

		local aimPart: string = library.flags.aimPart or 'Head';
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
			for _, entity in workspace.Live:GetChildren() do
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

localCheats:AddBind({
	text = 'Lock On',
	flag = 'Lock On Bind',
	tip = 'toggles lock on to the closest player to your mouse',
	mode = 'toggle',
	nomouse = true,
	callback = functions.lockOn
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
