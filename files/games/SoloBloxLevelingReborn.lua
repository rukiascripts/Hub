--!strict
--!optimize 2

local library = sharedRequire('UILibrary.lua');

local Utility = sharedRequire('utils/Utility.lua');
local Maid = sharedRequire('utils/Maid.lua');

local Services = sharedRequire('utils/Services.lua');

local ControlModule = sharedRequire('classes/ControlModule.lua');
local ToastNotif = sharedRequire('classes/ToastNotif.lua');

local column1, column2 = unpack(library.columns);

local ReplicatedStorage, Players, RunService, CollectionService, Lighting, UserInputService, VirtualInputManager, TeleportService, MemStorageService, TweenService, HttpService, Stats, NetworkClient, GuiService = Services:Get(
	'ReplicatedStorage',
	'Players',
	'RunService',
	'CollectionService',
	'Lighting',
	'UserInputService',
	'VirtualInputManager',
	'TeleportService',
	'MemStorageService',
	'TweenService',
	'HttpService',
	'Stats',
	'NetworkClient',
	'GuiService'
);

local LocalPlayer = Players.LocalPlayer;
local myRootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');

local functions = {};

if (game.PlaceId == 12214593747) then
	ToastNotif.new({
		text = 'Script will not run in menu!',
		duration = 5
	});
	task.delay(0.005, function()
		library:Unload();
	end);
	return;
end;

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait();

local maid = Maid.new();

local localcheats = column1:AddSection('Local Cheats');
local combatcheats = column1:AddSection('Combat Cheats');
local autofarmsection = column2:AddSection('Auto Farm');
local helpersection = column2:AddSection('Helpers');

local function getKey(name: string): RemoteEvent?
	for _, child in ReplicatedStorage:GetDescendants() do
		if (child:IsA('RemoteEvent') and child.Name == name) then
			return child;
		end;
	end;
	return nil;
end;

local GateEvent = getKey('GateEvent');
local AttackEvent = getKey('Mage_Combat_Event');
local DamageEvent = getKey('Mage_Combat_Damage_Event');
local SkillEvent = getKey('Mage_Skill_Event');
local DropEvent = getKey('DropEvent');

local DropFolder = workspace:WaitForChild('DropItem');

local DUNGEON_HELPER = {
	['D-Rank'] = {
		['Prison'] = {
			PlaceID = 127569336430170,
			Mobs = {'KARDING', 'HORIDONG', 'MAGICARABAO'}
		},
		['Rock'] = {
			PlaceID = 125357995526125,
			Mobs = {'KARDING', 'HORIDONG', 'MAGICARABAO'}
		}
	},
	['C-Rank'] = {
		['Subway'] = {
			PlaceID = 83492604633635,
			Mobs = {'WOLFANG', 'METALIC FANG', 'DAREWOLF', 'MONKEYKONG', 'UNDERWORLD SERPENT'}
		},
		['Goblin'] = {
			PlaceID = 71377998784000,
			Mobs = {'FANGORA', 'RAGNOK', 'TWINKLE', 'DARKFIRE', 'GOBLINS TYRANT'}
		}
	}
};

local CITY_PLACE_ID = 119482438738938;
local MOD_SOUND_ASSET = 'rbxassetid://367453005';
local PROXIMITY_NEAR_DISTANCE = 250;
local PROXIMITY_FAR_DISTANCE = 450;

function functions.speedHack(toggle: boolean): ()
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

function functions.fly(toggle: boolean): ()
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

function functions.infiniteJump(toggle: boolean): ()
	if (not toggle) then return end;

	repeat
		local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');
		if (rootPart and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
			rootPart.Velocity = Vector3.new(rootPart.Velocity.X, library.flags.infiniteJumpHeight, rootPart.Velocity.Z);
		end;
		task.wait(0.1);
	until not library.flags.infiniteJump;
end;

function functions.DungeonStats(rank: string?, dungeonName: string?): number?
	if (rank and dungeonName and DUNGEON_HELPER[rank] and DUNGEON_HELPER[rank][dungeonName]) then
		return DUNGEON_HELPER[rank][dungeonName].PlaceID;
	end;

	local mobFolder = workspace:WaitForChild('WalkingNPC');
	for _, mob in mobFolder:GetChildren() do
		if (mob:IsA('Highlight')) then continue; end;
		local root = mob:FindFirstChild('HumanoidRootPart');
		if (root and root:FindFirstChild('Health') and root.Health:FindFirstChild('ImageLabel')) then
			local tag = root.Health.ImageLabel:FindFirstChild('TextLabel');
			if (tag) then
				local mobName = tostring(tag.Text);
				for r, dungeons in DUNGEON_HELPER do
					for _, info in dungeons do
						if (table.find(info.Mobs, mobName)) then
							getgenv().DungeonRank = r;
							return info.PlaceID;
						end;
					end;
				end;
			end;
		end;
	end;

	return nil;
end;

function functions.Collect(dropModel: Model): ()
	if (not dropModel) then return end;
	local prompt = dropModel.Rotate.Attachment.ProximityPrompt;
	if (not prompt) then return end;
	prompt.MaxActivationDistance = math.huge;

	DropEvent:FireServer('Drop_Item', LocalPlayer, dropModel, dropModel.Name, prompt);
end;

function functions.createDungeon(userID: number, difficulty: string?, level: number?, placeIdTable: {number}?, dungeonRank: string?): ()
	local teleportArguments = {
		'Teleport',
		userID,
		{
			DIFFICULTY = difficulty or 'Hard',
			LEVEL = level or 90,
			PlaceID = placeIdTable or {
				71377998784000,
				83492604633635
			},
			RANK = dungeonRank or 'C-Rank'
		}
	};

	if (GateEvent) then
		GateEvent:FireServer(unpack(teleportArguments));
	end;
end;

function functions.GetRandomDungeon(selectedDungeons: {string}): (string?, string?)
	if (#selectedDungeons == 0) then return nil, nil; end;

	local dungeon = selectedDungeons[math.random(1, #selectedDungeons)];
	local rank = dungeon:match('%[(.-)%]');
	if (rank) then
		rank = rank:gsub(' ', '-');
		if (DUNGEON_HELPER[rank]) then
			return dungeon, rank;
		end;
	end;

	return nil, nil;
end;

function functions.StartSelectedDungeon(): ()
	local dungeonWithRank, rank = functions.GetRandomDungeon(getgenv().SelectedDungeons or {});
	if (not dungeonWithRank or not rank) then
		warn('No dungeon selected or invalid selection.');
		return;
	end;

	local dungeonName = dungeonWithRank:match('^(.-)%s*%[');
	if (not dungeonName) then
		warn('Failed to extract dungeon name from:', dungeonWithRank);
		return;
	end;

	local placeID = functions.DungeonStats(rank, dungeonName);
	if (not placeID) then
		warn('No PlaceID found for dungeon:', dungeonName);
		return;
	end;

	functions.createDungeon(
		LocalPlayer.UserId,
		getgenv().SelectedDifficulty or 'Hard',
		nil,
		{placeID},
		rank
	);
end;

function functions.GetHoverPosition(mobPos: Vector3): Vector3
	local method = getgenv().HoverMethod or 'Normal';
	local dist = getgenv().HoverDistance or 5;

	if (method == 'Normal') then
		return mobPos;
	elseif (method == 'Up') then
		return mobPos + Vector3.new(0, dist, 0);
	elseif (method == 'Down') then
		return mobPos - Vector3.new(0, dist, 0);
	elseif (method == 'Underground') then
		return mobPos - Vector3.new(0, 100, 0);
	end;

	return mobPos;
end;

function functions.ReturnToGround(): ()
	if (myRootPart) then
		myRootPart.CFrame = CFrame.new(myRootPart.Position.X, 5, myRootPart.Position.Z);
	end;
end;

function functions.GetSelectedPlaceIDs(selectedDungeons: {string}): {number}
	local placeIDs = {};
	for _, dungeon in selectedDungeons do
		local rank = dungeon:match('%[(.-)%]');
		rank = rank:gsub(' ', '-');
		if (DUNGEON_HELPER[rank]) then
			for _, id in DUNGEON_HELPER[rank]['PlaceID'] do
				table.insert(placeIDs, id);
			end;
		end;
	end;
	return placeIDs;
end;

function functions.ExtractSelectedDungeons(selectedTable: {[string]: boolean}): {string}
	local selectedList = {};
	for key, isSelected in selectedTable do
		local dungeonName;

		if (type(key) == 'table') then
			dungeonName = key[1];
		else
			dungeonName = key;
		end;

		if (isSelected and dungeonName) then
			table.insert(selectedList, dungeonName);
		end;
	end;
	return selectedList;
end;

function functions.HitMob(mobRoot: BasePart): ()
	if (not (mobRoot and mobRoot.Parent)) then return end;
	if (not LocalPlayer.Character or not myRootPart) then return end;
	myRootPart = Character.HumanoidRootPart;

	AttackEvent:FireServer(
		Character, 1, 'Mage',
		mobRoot.Position, Vector3.yAxis,
		mobRoot.Position, Vector3.yAxis,
		'Attack'
	);
	AttackEvent:FireServer(
		Character, 2, 'Mage',
		mobRoot.Position, Vector3.yAxis,
		mobRoot.Position, Vector3.yAxis,
		'Attack'
	);

	DamageEvent:FireServer(
		'Damage_Event_Combat',
		{
			char = Character,
			dodgedtable = mobRoot,
			blockedtable = mobRoot,
			perfecttable = mobRoot,
			hittedtable = mobRoot,
			class = 'Mage',
			skill = 'Combat',
			playerid = LocalPlayer.UserId
		}
	);

	SkillEvent:FireServer(
		Character, 'Mage7', 'Mage',
		mobRoot.Position, Vector3.yAxis,
		mobRoot.Position, Vector3.yAxis
	);
end;

local cutscene = false;
getgenv().StartedDungeon = false;

function functions.AutoFarmMob(toggle: boolean): ()
	if (not toggle) then
		getgenv().autoFarmMob = false;
		return;
	end;
	getgenv().autoFarmMob = true;

	while (getgenv().autoFarmMob) do
		task.wait(0.05);

		local gates = workspace:FindFirstChild('Gates');
		if (not gates) then return end;

		if (not getgenv().StartedDungeon) then
			for _, gate in gates:GetDescendants() do
				if (gate:IsA('BasePart') and gate.Name == 'Gate1') then
					firetouchinterest(myRootPart, gate, 0);
					task.wait(0.1);
					firetouchinterest(myRootPart, gate, 1);
					getgenv().StartedDungeon = true;
				end;
			end;
		end;

		repeat task.wait(); until getgenv().StartedDungeon;

		local mobFolder = workspace:WaitForChild('WalkingNPC');
		local foundMob = false;
		for _, model in mobFolder:GetChildren() do
			if (model:IsA('Highlight')) then continue end;
			local mob = model:FindFirstChild('HumanoidRootPart');
			if (mob and model.Name == 'Mobs5' and not cutscene) then
				getgenv().HoverMethod = 'Up';
				local newPos = functions.GetHoverPosition(mob.Position);
				myRootPart.CFrame = CFrame.new(newPos);
				task.wait(5);
				cutscene = true;
			end;
			if (mob) then
				foundMob = true;
				local newPos = functions.GetHoverPosition(mob.Position);
				myRootPart.CFrame = CFrame.new(newPos);
				functions.HitMob(mob);
			end;
		end;

		if (workspace:FindFirstChild('CloseRank')) then
			local oldCFrame = myRootPart.CFrame;
			task.wait(2);
			myRootPart.CFrame = CFrame.new(workspace.CloseRank.Position);
			task.wait(2);
			for _, obj in workspace.CloseRank:GetDescendants() do
				if (obj:IsA('ProximityPrompt')) then
					obj:InputHoldBegin();
				end;
			end;
			task.wait(2);
			myRootPart.CFrame = oldCFrame;
		end;

		if (not foundMob and not cutscene and getgenv().StartedDungeon) then
			local noMobCounter = 0;
			while (noMobCounter < 15 and not foundMob) do
				task.wait(0.35);

				foundMob = false;
				for _, model in mobFolder:GetChildren() do
					if (model:IsA('Highlight')) then continue end;
					local mob = model:FindFirstChild('HumanoidRootPart');
					if (mob) then
						foundMob = true;
						break;
					end;
				end;

				noMobCounter = noMobCounter + 1;
			end;

			if (not foundMob) then
				local finalGate = gates:FindFirstChild('Gate5') or gates:FindFirstChild('Gate4');
				if (finalGate and not workspace:FindFirstChild('CloseRank')) then
					myRootPart.CFrame = CFrame.new(finalGate.Position);
					task.wait(10);
				end;
			end;
		end;
	end;
end;

localcheats:AddDivider('Movement');

localcheats:AddToggle({
	text = 'Fly',
	callback = functions.fly
});

localcheats:AddSlider({
	flag = 'Fly Hack Value',
	min = 16,
	max = 500,
	value = 0,
	textpos = 2
});

localcheats:AddToggle({
	text = 'Speedhack',
	callback = functions.speedHack
});

localcheats:AddSlider({
	flag = 'Speed Hack Value',
	min = 16,
	max = 500,
	value = 0,
	textpos = 2
});

localcheats:AddToggle({
	text = 'Infinite Jump',
	callback = functions.infiniteJump
});

localcheats:AddSlider({
	flag = 'Infinite Jump Height',
	min = 50,
	max = 500,
	value = 0,
	textpos = 2
});

localcheats:AddDivider('Notifiers');

local MODERATOR_IDS = {
	74592177,    -- renzo
	2711295294,  -- raynee
	1943552960,  -- enko
	3458254657,  -- yno
	732367598,   -- mei
	279933005,   -- Vatsug
	3195344379,  -- ColdLikeAhki
	21992269,    -- Hilgrimz (Big Contributor)
	474810592,   -- ciansire22
	403928181,   -- Soryuu
	175682610,   -- Dawn
};

local modJoinSound = Instance.new('Sound');
modJoinSound.SoundId = MOD_SOUND_ASSET;
modJoinSound.Parent = workspace;

local function onPlayerAdded(player: Player): ()
	if (table.find(MODERATOR_IDS, player.UserId)) then
		modJoinSound:Play();
		ToastNotif.new({
			text = `Moderator joined [{player.Name}]`,
		});
	end;
end;

local function onPlayerRemoving(player: Player): ()
	if (table.find(MODERATOR_IDS, player.UserId)) then
		modJoinSound:Play();
		ToastNotif.new({
			text = `Moderator left [{player.Name}]`,
		});
	end;
end;

Players.PlayerAdded:Connect(onPlayerAdded);
Players.PlayerRemoving:Connect(onPlayerRemoving);

function functions.playerProximityCheck(toggle: boolean): ()
	if (not toggle) then
		maid.proximityCheck = nil;
		return;
	end;

	local notifSend = setmetatable({}, {
		__mode = 'k';
	});

	maid.proximityCheck = RunService.Heartbeat:Connect(function()
		if (not myRootPart) then return end;

		for _, v in Players:GetPlayers() do
			local rootPart = v.Character and v.Character.PrimaryPart;
			if (not rootPart or v == LocalPlayer) then continue end;

			local distance = (myRootPart.Position - rootPart.Position).Magnitude;

			if (distance < PROXIMITY_NEAR_DISTANCE and not table.find(notifSend, rootPart)) then
				table.insert(notifSend, rootPart);
				ToastNotif.new({
					text = `{v.Name} is nearby [{math.floor(distance)}]`,
					duration = 30
				});
			elseif (distance > PROXIMITY_FAR_DISTANCE and table.find(notifSend, rootPart)) then
				table.remove(notifSend, table.find(notifSend, rootPart));
				ToastNotif.new({
					text = `{v.Name} is no longer nearby [{math.floor(distance)}]`,
					duration = 30
				});
			end;
		end;
	end);
end;

localcheats:AddToggle({
	text = 'Player Proximity Check',
	tip = 'Gives you a warning when a player is close to you',
	callback = functions.playerProximityCheck
});

combatcheats:AddDivider('Player');

combatcheats:AddList({
	values = {'Normal', 'Up', 'Down', 'Underground'},
	text = 'Hover Method',
	tip = 'How your character positions relative to mobs',
	callback = function(val)
		getgenv().HoverMethod = val;
	end
});
getgenv().HoverMethod = 'Normal';

combatcheats:AddSlider({
	text = 'Hover Distance (Y)',
	value = 5,
	min = -50,
	max = 50,
	tip = 'How far above/below mobs you hover',
	callback = function(val)
		getgenv().HoverDistance = val;
	end
});
getgenv().HoverDistance = 5;

combatcheats:AddToggle({
	text = 'Auto Farm Mobs',
	default = false,
	callback = functions.AutoFarmMob
});

combatcheats:AddToggle({
	text = '[Vis]skillspam',
	default = false,
	callback = function(state)
		getgenv().AntiSkillSpam = state;
	end
});

workspace.ChildAdded:Connect(function(child)
	if (child:IsA('Model') and child.Name == 'Blizzmancer' and getgenv().AntiSkillSpam) then
		child:Destroy();
	end;
end);

autofarmsection:AddDivider('Teleport to Dungeon');

autofarmsection:AddList({
	text = 'Select Dungeon',
	values = {
		'Prison [D Rank]',
		'Rock [D Rank]',
		'Subway [C Rank]',
		'Goblin [C Rank]',
	},
	multiselect = true,
	callback = function(selectedTable)
		getgenv().SelectedDungeons = functions.ExtractSelectedDungeons(selectedTable);
		print('Selected dungeons:', HttpService:JSONEncode(getgenv().SelectedDungeons));
	end;
});

autofarmsection:AddList({
	text = 'Dungeon Difficulty',
	values = {
		'Easy',
		'Medium',
		'Hard'
	},
	multiselect = false,
	callback = function(value)
		getgenv().SelectedDifficulty = value;
	end;
});

autofarmsection:AddToggle({
	text = 'Auto Start Dungeon',
	tip = 'Put script within Auto Execute.',
	callback = function(value)
		if (value and game.PlaceId == CITY_PLACE_ID) then
			task.wait(5);
			if (value) then
				functions.StartSelectedDungeon();
			end;
		end;
	end;
});

autofarmsection:AddButton({
	text = 'Create & Start Dungeon',
	tip = 'Teleports to a random selected dungeon.',
	callback = function()
		functions.StartSelectedDungeon();
	end;
});

autofarmsection:AddToggle({
	text = 'Auto Collect Drops',
	callback = function(state)
		getgenv().AutoCollect = state;
		if (not getgenv().AutoCollect) then
			if (getgenv().DropConnection) then
				getgenv().DropConnection:Disconnect();
				getgenv().DropConnection = nil;
			end;
			return;
		end;
		getgenv().DropConnection = DropFolder.ChildAdded:Connect(function(drop)
			if (getgenv().AutoCollect) then
				task.wait(0.05);
				functions.Collect(drop);
			end;
		end);
		while (getgenv().AutoCollect) do
			task.wait(0.5);
			for _, drop in DropFolder:GetChildren() do
				if (drop:IsA('Model')) then
					functions.Collect(drop);
				end;
			end;
		end;
	end
});

helpersection:AddDivider('Teleports');

helpersection:AddButton({
	text = 'Return to City',
	tip = 'Teleports to the city',
	callback = function()
		TeleportService:Teleport(CITY_PLACE_ID, LocalPlayer);
	end;
});
