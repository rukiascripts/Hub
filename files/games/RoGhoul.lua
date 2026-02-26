local Services = sharedRequire('utils/Services.lua');
local library = sharedRequire('UILibrary.lua');
local ToastNotif = sharedRequire('classes/ToastNotif.lua');

local column1, column2 = unpack(library.columns);

local Players, ReplicatedStorage, TweenService, RunService, TeleportService = Services:Get('Players', 'ReplicatedStorage', 'TweenService', 'RunService', 'TeleportService');

local LocalPlayer: Player = Players.LocalPlayer;

local TWEEN_SPEED: number = 100;
local MOB_TIMEOUT: number = 60;
local CASHOUT_INTERVAL: number = 3600;
local CORPSE_CLICK_COUNT: number = 5;
local SAFE_ZONE_RAY_DISTANCE: number = -25;
local ATTACK_HEIGHT_OFFSET: number = 5;
local ATTACK_DISTANCE: number = 2.5;
local NPC_TELEPORT_DISTANCE: number = 25;

local KAGUNE_STAGES: { [number]: string } = {
	[0] = 'Zero',
	[1] = 'One',
	[2] = 'Two',
	[3] = 'Three',
	[4] = 'Four',
	[5] = 'Five',
	[6] = 'Six',
	[7] = 'Seven',
	[8] = 'Eight',
	[9] = 'Nine',
};

local FOCUS_TYPES: { string } = {
	'Physical',
	'Kagune',
	'Durability',
	'Speed',
};

print('RO GHOUL FOUND!');

local clientControl: Instance?;
repeat
	print('Waiting for game to start ...');
	clientControl = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('ClientControl');
	task.wait(0.5);
until clientControl and not (clientControl :: any).Disabled;

local playerTeam: string = LocalPlayer.PlayerFolder.Customization.Team.Value;

local remoteKey: string?;
for _: number, v: any in next, getgc() do
	if (typeof(v) == 'function') then
		local constants: { string }? = islclosure(v) and getconstants(v);
		if (constants and table.find(constants :: { string }, 'KeyEvent')) then
			remoteKey = (constants :: { string })[table.find(constants :: { string }, 'KeyEvent') + 1];
			break;
		end;
	end;
end;

if (not remoteKey or typeof(remoteKey) ~= 'string') then
	print(remoteKey);
	return LocalPlayer:Kick('\nError 404-A(RoGhoul). Make a support ticket if that happens again!');
end;

print('GotKey', remoteKey);

local autoFarmWorkings: { [string]: boolean } = {
	autoFarm = false,
	cashoutReputation = false,
	autoTrainer = false,
};

local currentTween: Tween?;
local bodyVelocity: BodyVelocity?;
local lastMobAttack: number = 0;
local lastCashout: number = 0;

--[[
	checks if any other auto farm type is currently running besides the excluded one
	@param exclude string
	@return boolean?
]]
local function IsAnyFarmActive(exclude: string): boolean?
	for key: string, value: any in next, autoFarmWorkings do
		if (typeof(value) == 'boolean' and value and key ~= exclude) then
			return true;
		end;
	end;
	return nil;
end;

--[[
	waits until no other farm type is running before proceeding
	@param autoFarmType string
]]
local function QueueFarm(autoFarmType: string): ()
	print('QUEUE STARTED!');
	autoFarmWorkings[autoFarmType] = true;
	repeat task.wait(); until not IsAnyFarmActive(autoFarmType);
	print('QUEUE FINISHED!');
end;

--[[
	checks if a mob root part is sitting inside a safe zone via raycast
	@param rootPart BasePart
	@return boolean
]]
local function IsMobInSafeZone(rootPart: BasePart): boolean
	local rayCastParams: RaycastParams = RaycastParams.new();
	rayCastParams.FilterType = Enum.RaycastFilterType.Whitelist;
	rayCastParams.FilterDescendantsInstances = { workspace.SafeZones };

	local result: boolean = workspace:Raycast(rootPart.Position, Vector3.new(0, SAFE_ZONE_RAY_DISTANCE, 0), rayCastParams) and true or false;
	if (result) then
		warn('MOB IN SAFEZONE!');
	end;

	return result;
end;

--[[
	checks if we should attack this mob based on focus settings
	@param mob Model
	@return boolean
]]
local function CanAttack(mob: Model): boolean
	if (string.find(mob.Name, 'Investigator') and library.flags.focusInvestigator) then
		return true;
	end;

	if (string.find(mob.Name, 'Aogiri') and library.flags.focusAogiri) then
		return true;
	end;

	if (mob.Parent.Name == 'HumanSpawns' and library.flags.focusHuman) then
		return true;
	end;

	if (mob.Parent.Name == 'BossSpawns' and library.flags.focusBoss) then
		return true;
	end;

	return false;
end;

--[[
	checks if a mob matches the current quest target
	@param mob Model
	@param questTarget string
	@return boolean
]]
local function CanAttackQuest(mob: Model, questTarget: string): boolean
	if (string.find(mob.Name, 'Investigator') and string.find(questTarget, 'Investigator')) then
		return true;
	end;

	if (string.find(mob.Name, 'Aogiri') and string.find(questTarget, 'Aogiri')) then
		return true;
	end;

	if (mob.Parent.Name == 'HumanSpawns' and string.find(questTarget, 'Human')) then
		return true;
	end;

	return false;
end;

--[[
	fires a key event to the server through the characters remotes
	@param ... any
]]
local function FireServer(...: any): ()
	local character: Model? = LocalPlayer.Character;
	if (not character) then return; end;

	local remotes: Instance? = (character :: Model):FindFirstChild('Remotes');
	if (not remotes) then return; end;

	local keyEvent: Instance? = (remotes :: Instance):FindFirstChild('KeyEvent');
	if (not keyEvent) then return; end;

	(keyEvent :: RemoteEvent):FireServer(remoteKey, ...);
end;

--[[
	creates or reuses a body velocity on the given root part
	@param myRootPart BasePart
]]
local function CreateBodyVelocity(myRootPart: BasePart): ()
	if (bodyVelocity and (bodyVelocity :: BodyVelocity).Parent ~= myRootPart) then
		(bodyVelocity :: BodyVelocity):Destroy();
		bodyVelocity = nil;
	end;

	bodyVelocity = bodyVelocity or Instance.new('BodyVelocity');
	(bodyVelocity :: BodyVelocity).Velocity = Vector3.new();
	(bodyVelocity :: BodyVelocity).Parent = myRootPart;
end;

--[[
	tweens the root part to a position and waits for it to finish
	@param rootPart BasePart
	@param position Vector3
]]
local function TweenTeleport(rootPart: BasePart, position: Vector3): ()
	local tweenInfo: TweenInfo = TweenInfo.new((rootPart.Position - position).Magnitude / TWEEN_SPEED, Enum.EasingStyle.Linear);
	local tween: Tween = TweenService:Create(rootPart, tweenInfo, { CFrame = CFrame.new(position) });

	tween:Play();
	tween.Completed:Wait();
end;

--[[
	checks if a mob is dead or timed out
	@param mob Model
	@return boolean?, boolean?
]]
local function IsMobDead(mob: Model): (boolean?, boolean?)
	local now: number = DateTime.now().UnixTimestampMillis / 1000;

	if (now - lastMobAttack >= MOB_TIMEOUT) then
		return true;
	end;

	if (mob.Parent == nil) then
		print('Mob Not In Workspace');
		return true;
	end;

	local mobRoot: BasePart? = mob.PrimaryPart;
	if (mobRoot and (mobRoot :: BasePart).Position.Y <= 25) then
		return true;
	end;

	if (mob:FindFirstChild(`{mob.Name} Corpse`)) then
		return true, true;
	end;

	return nil;
end;

--[[
	clicks on a corpse a few times to eat it
	@param clickPart ClickDetector
]]
local function EatCorpse(clickPart: ClickDetector): ()
	print('Found corpse');

	for _: number = 1, CORPSE_CLICK_COUNT do
		pcall(fireclickdetector, clickPart);
		task.wait(0.1);
	end;
end;

--[[
	converts focus type name to the server-expected format. kagune maps to weapon for some reason
	@param value string
	@return string
]]
local function ConvertFocusType(value: string): string
	if (value == 'Kagune') then
		return 'Weapon';
	end;

	return value;
end;

--[[
	finds the closest mob we can attack, factoring in boss priority and quest targets
	@return Model?, number, BasePart?, boolean
]]
local function GetClosestMob(): (Model?, number, BasePart?, boolean)
	local currentMob: Model? = nil;
	local currentDistance: number = math.huge;
	local mobIsBoss: boolean = false;
	local myRootPart: BasePart? = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart;

	local priorities: { [string]: number } = {
		Eto = library.flags.etoPriority,
		Koutarou = library.flags.koutarouPriority,
		Nishiki = library.flags.nishikiPriority,
	};

	local allMobs: { { mob: Model, mobDistance: number, root: BasePart, isBoss: boolean } } = {};

	for _: number, v: Instance in next, workspace.NPCSpawns:GetChildren() do
		local isMob: Model? = v:FindFirstChildOfClass('Model');
		if (isMob and myRootPart) then
			local root: BasePart? = (isMob :: Model).PrimaryPart;
			local mobDistance: number? = root and (root.Position - (myRootPart :: BasePart).Position).Magnitude;

			if (mobDistance and not IsMobInSafeZone(root :: BasePart)) then
				table.insert(allMobs, {
					mob = isMob :: Model,
					mobDistance = mobDistance :: number,
					root = root :: BasePart,
					isBoss = v.Name == 'BossSpawns',
				});
			end;
		end;
	end;

	local highest: number = 0;
	local targetBoss: { mob: Model, mobDistance: number, root: BasePart, isBoss: boolean }? = nil;

	for _: number, mob: { mob: Model, mobDistance: number, root: BasePart, isBoss: boolean } in next, allMobs do
		if (mob.isBoss) then
			for priorityBoss: string, priorityValue: number in next, priorities do
				if (mob.mob.Name:find(priorityBoss) and highest < priorityValue and priorityValue > 0) then
					highest = priorityValue;
					targetBoss = mob;
				end;
			end;
		end;
	end;

	if (targetBoss and library.flags.focusBoss) then
		return (targetBoss :: any).mob, (targetBoss :: any).mobDistance, myRootPart :: BasePart;
	end;

	if (library.flags.toggleAutoQuest) then
		local questTarget: string? = nil;
		local questTargetObject: any = nil;
		local maxTarget: number = 1;
		local currentTarget: number = 0;

		local currentQuest = LocalPlayer.PlayerFolder.CurrentQuest;

		for _: number, v: Instance in next, currentQuest.Complete:GetChildren() do
			if (v.Name ~= 'Reward') then
				questTarget = v.Name;
				questTargetObject = v;
			end;
		end;

		if (questTargetObject) then
			currentTarget = questTargetObject.Value;
			maxTarget = questTargetObject.Max.Value;
		end;

		if (questTarget == nil or maxTarget == currentTarget) then
			local myTeam: string = playerTeam == 'CCG' and 'Yoshitoki' or 'Yoshimura';
			local reputationPosition: Vector3 = workspace:FindFirstChild(myTeam, true):GetPrimaryPartCFrame().p;

			local myRoot: BasePart? = myRootPart;
			local distanceFrom: number = ((myRoot :: BasePart).Position - reputationPosition).Magnitude;
			repeat
				myRoot = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart;
				if (myRoot) then
					distanceFrom = ((myRoot :: BasePart).Position - reputationPosition).Magnitude;
					TweenService:Create(
						myRoot :: BasePart,
						TweenInfo.new(distanceFrom / TWEEN_SPEED),
						{ CFrame = CFrame.new(reputationPosition) }
					):Play();
				end;
				task.wait(0.5);
			until myRoot and ((myRoot :: BasePart).Position - reputationPosition).Magnitude <= NPC_TELEPORT_DISTANCE;
			task.wait(2.5);
			for _: number = 1, 2 do
				print(ReplicatedStorage.Remotes[myTeam].Task:InvokeServer());
				task.wait(2.5);
			end;
		end;

		for _: number, v: Instance in next, LocalPlayer.PlayerFolder.CurrentQuest.Complete:GetChildren() do
			if (v.Name ~= 'Reward') then
				questTarget = v.Name;
			end;
		end;

		local questMob: Model? = nil;
		local questDistance: number = math.huge;

		for _: number, mob: { mob: Model, mobDistance: number, root: BasePart, isBoss: boolean } in next, allMobs do
			local mobHumanoid: Humanoid? = mob.mob:FindFirstChildOfClass('Humanoid');

			if (mobHumanoid and (mobHumanoid :: Humanoid).Health > 25 and CanAttackQuest(mob.mob, questTarget :: string)) then
				if (mob.mobDistance < questDistance) then
					questMob = mob.mob;
					questDistance = mob.mobDistance;
					mobIsBoss = mob.isBoss;
				end;
			end;
		end;

		if (questMob) then
			return questMob, questDistance, myRootPart :: BasePart;
		end;
	end;

	for _: number, mob: { mob: Model, mobDistance: number, root: BasePart, isBoss: boolean } in next, allMobs do
		local mobHumanoid: Humanoid? = mob.mob:FindFirstChildOfClass('Humanoid');

		if (mobHumanoid and (mobHumanoid :: Humanoid).Health > 25 and CanAttack(mob.mob)) then
			if (mob.mobDistance < currentDistance) then
				currentMob = mob.mob;
				currentDistance = mob.mobDistance;
				mobIsBoss = mob.isBoss;
			end;
		end;
	end;

	return currentMob, currentDistance, myRootPart :: BasePart, mobIsBoss;
end;

local function ToggleAutoFarm(toggle: boolean): ()
	if (not toggle) then
		if (bodyVelocity) then
			(bodyVelocity :: BodyVelocity):Destroy();
			bodyVelocity = nil;
		end;

		if (currentTween) then
			(currentTween :: Tween):Cancel();
			currentTween = nil;
		end;
		return;
	end;

	repeat
		local mob: Model?, mobDistance: number, myRootPart: BasePart?, isMobBoss: boolean = GetClosestMob();

		if (mob and myRootPart and not IsAnyFarmActive('autoFarm')) then
			autoFarmWorkings.autoFarm = true;
			CreateBodyVelocity(myRootPart :: BasePart);
			local tweenInfo: TweenInfo = TweenInfo.new(mobDistance / TWEEN_SPEED);
			lastMobAttack = DateTime.now().UnixTimestampMillis / 1000;

			local tween: Tween = TweenService:Create(myRootPart :: BasePart, tweenInfo, {
				CFrame = CFrame.new((mob :: Model).PrimaryPart.CFrame.p),
			});
			tween:Play();
			currentTween = tween;

			repeat
				RunService.Heartbeat:Wait();
			until IsMobDead(mob :: Model) or tween.PlaybackState ~= Enum.PlaybackState.Playing or not library.flags.toggleAutoFarm;

			if (not library.flags.toggleAutoFarm) then
				if (currentTween) then
					(currentTween :: Tween):Cancel();
					currentTween = nil;
				end;
				autoFarmWorkings.autoFarm = false;
				return;
			end;

			if (tween.PlaybackState == Enum.PlaybackState.Completed) then
				local lastFire: number = 0;

				repeat
					local character: Model? = LocalPlayer.Character;
					local innerRootPart: BasePart? = character and (character :: Model).PrimaryPart;
					local mobRoot: BasePart? = (mob :: Model).PrimaryPart;

					if (innerRootPart and mobRoot) then
						CreateBodyVelocity(innerRootPart :: BasePart);
						(innerRootPart :: BasePart).CFrame = CFrame.new((mobRoot :: BasePart).CFrame * ((mobRoot :: BasePart).CFrame.LookVector * ATTACK_DISTANCE)) * CFrame.new(0, ATTACK_HEIGHT_OFFSET, 0) * CFrame.Angles(math.rad(-90), 0, 0);

						local now: number = DateTime.now().UnixTimestampMillis / 1000;

						if (not ((character :: Model):FindFirstChild('Kagune') or (character :: Model):FindFirstChild('Katana') or (character :: Model):FindFirstChild('Quinque'))) then
							FireServer(KAGUNE_STAGES[library.flags.kaguneStage or 1], 'Down', nil, 'ShiftLock', workspace.CurrentCamera.CFrame);
							task.wait(2);
						elseif (now - lastFire >= 0.1) then
							FireServer('Mouse1', 'Down', nil, 'ShiftLock', workspace.CurrentCamera.CFrame);

							if (isMobBoss) then
								FireServer('E', 'Down', nil, 'ShiftLock', workspace.CurrentCamera.CFrame);
								FireServer('R', 'Down', nil, 'ShiftLock', workspace.CurrentCamera.CFrame);
								FireServer('F', 'Down', nil, 'ShiftLock', workspace.CurrentCamera.CFrame);
							end;

							lastFire = now;
						end;
					end;

					if (not library.flags.toggleAutoFarm) then
						return;
					end;
					RunService.Heartbeat:Wait();
				until IsMobDead(mob :: Model) or not library.flags.toggleAutoFarm;
			end;

			if (not library.flags.toggleAutoFarm) then
				autoFarmWorkings.autoFarm = false;
				return;
			end;

			local isDead: boolean?, canEat: boolean? = IsMobDead(mob :: Model);

			if (isDead and canEat and library.flags.eatCorpse) then
				task.wait(0.5);
				local mobCorpse: Instance? = (mob :: Model):FindFirstChild(`{(mob :: Model).Name} Corpse`);
				local clickPart: ClickDetector? = mobCorpse and (mobCorpse :: Instance):FindFirstChildWhichIsA('ClickDetector', true);

				if (clickPart) then
					TweenTeleport(myRootPart :: BasePart, (clickPart :: Instance).Parent.Position);
					EatCorpse(clickPart :: ClickDetector);
				else
					print('no click part!');
				end;

				print(clickPart);
				task.wait(0.2);
			end;

			autoFarmWorkings.autoFarm = false;
		end;
		task.wait(0.5);
	until not library.flags.toggleAutoFarm;
end;

local function ToggleCashOutReputation(toggle: boolean): ()
	if (not toggle) then
		return;
	end;

	repeat
		local now: number = DateTime.now().UnixTimestampMillis / 1000;

		if (now - lastCashout >= CASHOUT_INTERVAL and LocalPlayer.Character and LocalPlayer.Character.PrimaryPart) then
			QueueFarm('cashoutReputation');
			print('HEY IM CASHOUT IM DOING MY STUFF END IN 10SEC');

			local myTeam: string = playerTeam == 'CCG' and 'Yoshitoki' or 'Yoshimura';
			local reputationPosition: Vector3 = workspace:FindFirstChild(myTeam, true):GetPrimaryPartCFrame().p;

			local myRoot: BasePart? = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart;
			local distanceFrom: number = ((myRoot :: BasePart).Position - reputationPosition).Magnitude;
			repeat
				myRoot = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart;
				if (myRoot) then
					distanceFrom = ((myRoot :: BasePart).Position - reputationPosition).Magnitude;
					TweenService:Create(
						myRoot :: BasePart,
						TweenInfo.new(distanceFrom / TWEEN_SPEED),
						{ CFrame = CFrame.new(reputationPosition) }
					):Play();
				end;
				task.wait(0.5);
			until myRoot and ((myRoot :: BasePart).Position - reputationPosition).Magnitude <= NPC_TELEPORT_DISTANCE;
			task.wait(2.5);
			ReplicatedStorage.Remotes.ReputationCashOut:InvokeServer();
			lastCashout = DateTime.now().UnixTimestampMillis / 1000;
			task.wait(2.5);
			autoFarmWorkings.cashoutReputation = false;
			print('HEY IM CASHOUT I\'VE DONE THE STUFF');
			task.wait(1);
		else
			local remaining: number = CASHOUT_INTERVAL - (now - lastCashout);
			print(`CASHOUT CAN ONLY CASH OUT IN {remaining} SECONDS`);
		end;
		task.wait(1);
	until not library.flags.cashoutReputation;
end;

local function ToggleAutoFocus(toggle: boolean): ()
	if (not toggle) then
		return;
	end;

	repeat
		local totalFocusPoint: number = 0;

		for _: number, v: string in next, FOCUS_TYPES do
			totalFocusPoint += library.flags[string.lower(v)];
		end;

		local playerFocus: number = tonumber(LocalPlayer.PlayerFolder.Stats.Focus.Value) or 0;

		if (playerFocus >= totalFocusPoint) then
			for _: number, v: string in next, FOCUS_TYPES do
				LocalPlayer.PlayerFolder.StatsFunction:InvokeServer(
					'Focus',
					`{ConvertFocusType(v)}AddButton`,
					library.flags[string.lower(v)]
				);
			end;
		end;
		task.wait(0.5);
	until not library.flags.toggleAutoFocus;
end;

local function ToggleAutoTrainer(toggle: boolean): ()
	if (not toggle) then
		return;
	end;

	repeat
		QueueFarm('autoTrainer');
		local data: any = ReplicatedStorage.Remotes.Trainers.RequestTraining:InvokeServer(LocalPlayer.PlayerFolder.Trainers[`{playerTeam}Trainer`].Value);
		print(data, data == nil, data == '');
		if (data ~= nil) then
			autoFarmWorkings.autoTrainer = false;
		end;
		task.wait(10);
	until not library.flags.toggleAutoTrainer;
end;

local function SetDataloss(toggle: boolean): ()
	pcall(function(): ()
		local spawnLocationValue = LocalPlayer.PlayerFolder.Settings.SpawnLocation;
		local currentSpawn: string = spawnLocationValue.Value:gsub('\128', '');

		originalFunctions.fireServer(ReplicatedStorage.Remotes.Settings.SpawnSelection, toggle and `{currentSpawn}\128` or currentSpawn);

		spawnLocationValue:GetPropertyChangedSignal('Value'):Once(function(): ()
			spawnLocationValue.Value = currentSpawn;
		end);

		ToastNotif.new({
			text = toggle and 'Dataloss set' or 'Dataloss unset',
		});
	end);
end;

RunService.Stepped:Connect(function(): ()
	local character: Model? = LocalPlayer.Character;
	if (not character) then return; end;
	if (not library.flags.toggleAutoFarm and not library.flags.cashoutReputation) then return; end;

	for _: number, v: Instance in next, (character :: Model):GetChildren() do
		if (v:IsA('BasePart')) then
			(v :: BasePart).CanCollide = false;
		end;
	end;
end);

local oldNamecall: (...any) -> ...any;
oldNamecall = hookmetamethod(game, '__namecall', function(...: any): ...any
	SX_VM_CNONE();
	local method: string = getnamecallmethod();
	local self: any = ...;

	if (typeof(self) ~= 'Instance') then
		return oldNamecall(...);
	end;

	if (method == 'Destroy' and tostring(self) == 'TSCodeVal' and library.flags.toggleAutoTrainer) then
		local caller: any = getfenv(2).script;
		local trainer: any = caller.TrainingSession.Value;

		task.delay(1, function(): ()
			trainer.Comm.FireServer(trainer.Comm, 'Finished', self.Value, false);
			autoFarmWorkings.autoTrainer = false;
		end);
	end;

	return oldNamecall(...);
end);

local autoFarm = column1:AddSection('Auto Farm');
local autoFocus = column2:AddSection('Auto Focus');
local autoTrainer = column2:AddSection('Auto Trainer');
local dataloss = column2:AddSection('Dataloss');

autoFarm:AddToggle({ text = 'Toggle Auto Farm', callback = ToggleAutoFarm });
autoFarm:AddToggle({ text = 'Focus Investigator' });
autoFarm:AddToggle({ text = 'Focus Aogiri' });
autoFarm:AddToggle({ text = 'Focus Human' });
autoFarm:AddToggle({ text = 'Focus Boss' });
autoFarm:AddToggle({ text = 'Toggle Auto Quest' });
autoFarm:AddToggle({ text = 'CashOut Reputation', callback = ToggleCashOutReputation });
autoFarm:AddToggle({ text = 'Eat Corpse' });

autoFarm:AddSlider({ text = 'Kagune Stage', min = 1, max = 6 });
autoFarm:AddSlider({ text = 'Eto Priority', value = 3, min = 0, max = 3 });
autoFarm:AddSlider({ text = 'Koutarou Priority', value = 2, min = 0, max = 3 });
autoFarm:AddSlider({ text = 'Nishiki Priority', min = 0, max = 3 });

autoFocus:AddToggle({ text = 'Toggle Auto Focus', callback = ToggleAutoFocus });
autoFocus:AddSlider({ text = 'Physical', min = 1, max = 10 });
autoFocus:AddSlider({ text = 'Kagune', min = 1, max = 10 });
autoFocus:AddSlider({ text = 'Durability', min = 1, max = 10 });
autoFocus:AddSlider({ text = 'Speed', min = 1, max = 10 });

autoTrainer:AddToggle({ text = 'Enable', flag = 'Toggle Auto Trainer', callback = ToggleAutoTrainer });

dataloss:AddButton({
	text = 'Set dataloss',
	callback = function(): () SetDataloss(true); end,
});

dataloss:AddButton({
	text = 'Unset dataloss',
	callback = function(): () SetDataloss(false); end,
});

dataloss:AddButton({
	text = 'Rejoin',
	callback = function(): () TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId); end,
});
