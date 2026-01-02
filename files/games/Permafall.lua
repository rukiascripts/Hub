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

if (game.PlaceId == 126222071643660) then
    ToastNotif.new({
        text = 'Script will not run in menu!',
        duration = 5
    });

    task.delay(0.005, function()
        library:Unload();
    end);
    return;
end;


local column1, column2 = unpack(library.columns);

local functions = {};

local Players, RunService, UserInputService, HttpService, CollectionService, MemStorageService = Services:Get('Players', 'RunService', 'UserInputService', 'HttpService', 'CollectionService', 'MemStorageService');
local LocalPlayer = Players.LocalPlayer;

local maid = Maid.new();

local localcheats = column1:AddSection('Local Cheats');
local misccheats = column1:AddSection('Misc');
local playercheats = column2:AddSection('Player Cheats');


do -- // Functions
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

            if (not CollectionService:HasTag(maid.speedHackBv, 'good')) then
                CollectionService:AddTag(maid.speedHackBv, 'good');
            end;

            maid.speedHackBv.Parent = not library.flags.fly and rootPart or nil;
            maid.speedHackBv.Velocity = (humanoid.MoveDirection.Magnitude ~= 0 and humanoid.MoveDirection or gethiddenproperty(humanoid, 'WalkDirection')) * library.flags.speedHackValue;
        end);
    end;


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

            if (not CollectionService:HasTag(maid.flyBv, 'good')) then
                CollectionService:AddTag(maid.flyBv, 'good');
            end;

            maid.flyBv.Parent = rootPart;
            maid.flyBv.Velocity = camera.CFrame:VectorToWorldSpace(ControlModule:GetMoveVector() * library.flags.flyHackValue);
        end);
    end;


    function functions.infiniteJump(toggle)
        if(not toggle) then return end;

        repeat
            local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart');
            if(rootPart and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
                rootPart.Velocity = Vector3.new(rootPart.Velocity.X, library.flags.infiniteJumpHeight, rootPart.Velocity.Z);
            end;
            task.wait(0.1);
        until not library.flags.infiniteJump;
    end;

    function functions.antiFire(toggle)
        if(not toggle) then
            maid.antiFire = nil;
            return;
        end;
        print('hell2o')
        maid.antiFire = LocalPlayer.Character.Values.OnFire.Changed:Connect(function(boolean)
            print('bro')
            if(boolean) then
                print('mimic')
                local args = {
                    {
                        Enabled = true,
                        Character = game:GetService("Players").LocalPlayer.Character,
                        InputType = "Dash"
                    }
                }
                game:GetService("Players").LocalPlayer.Character:WaitForChild("Communicate"):FireServer(unpack(args))
            end;
        end);
    end;
end;

-- NoClip
	do
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
				debug.profilebegin('noclip');

				local myCharacterParts = Utility:getPlayerData().parts;
				local isKnocked = effectReplicator:FindEffect('Knocked');
				local disableNoClipWhenKnocked = library.flags.disableNoClipWhenKnocked;

				for _, v in next, myCharacterParts do
					if (disableNoClipWhenKnocked) then
						v.CanCollide = not not isKnocked;
					else
						v.CanCollide = false;
					end;
				end;
				debug.profileend();
			end);
		end;
	end;

	function functions.clickDestroy(toggle)
		if (not toggle) then
			maid.clickDestroy = nil;
			return;
		end;

		maid.clickDestroy = UserInputService.InputBegan:Connect(function(input, gpe)
			if (input.UserInputType ~= Enum.UserInputType.MouseButton1 or gpe) then return end;

			local target = playerMouse.Target;
			if (not target or target:IsA('Terrain')) then return end;

			target:Destroy();
		end)
	end;

	function functions.serverHop(bypass)
		if(bypass or library:ShowConfirm('Are you sure you want to switch server?')) then
			library:UpdateConfig();
			local dataSlot = LocalPlayer:GetAttribute('DataSlot');
			MemStorageService:SetItem('DataSlot', dataSlot);

			BlockUtils:BlockRandomUser();
			TeleportService:Teleport(4111023553);
		end;
	end;

	local function tweenTeleport(rootPart, position, noWait)
		local distance = (rootPart.Position - position).Magnitude;
		local tween = TweenService:Create(rootPart, TweenInfo.new(distance / 120, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(position)
		});

		tween:Play();

		if (not noWait) then
			tween.Completed:Wait();
		end;

		return tween;
	end;


localcheats:AddDivider("Movement");


localcheats:AddToggle({
    text = 'Fly',
    callback = functions.fly

});

localcheats:AddSlider({
    flag = 'Fly Hack Value', 
    min = 16, 
    max = 200, 
    value = 0, 
    textpos = 2});
localcheats:AddToggle({
    text = 'Speedhack',
    callback = functions.speedHack
});
localcheats:AddSlider({
    flag = 'Speed Hack Value', 
    min = 16, 
    max = 200, 
    value = 0, 
    textpos = 2});
localcheats:AddToggle({
    text = 'Infinite Jump',
    callback = functions.infiniteJump
});
localcheats:AddSlider({
    flag = 'Infinite Jump Height', 
    min = 50, 
    max = 250, 
    value = 0, 
    textpos = 2
});

localcheats:AddToggle({
    text = 'No Clip',
    callback = functions.noClip
});

localcheats:AddToggle({
    text = 'Click Destroy',
    callback = functions.clickDestroy
});

function functions.Respawn(resp)
    if(resp or library:ShowConfirm('Are you sure you want to respawn?')) then
        game.Players.LocalPlayer.Character.Humanoid.Health = 0
    end
end

do -- // MISC CHEATS
    misccheats:AddButton({
        text = 'Respawn',
        tip = 'Respawns the player (Kills them)',
        callback = functions.Respawn
    });

    misccheats:AddButton({
        text = 'Server Hop',
        callback = functions.serverHop
    });

end;


playercheats:AddDivider("Player Settings");

playercheats:AddToggle({
    text = 'Anti Fire',
    callback = functions.antiFire
});


local VisualsMisc = column2:AddSection('Visuals');
VisualsMisc:AddDivider("Game Visuals");
local Lighting = game:GetService("Lighting")

local oldAmbient, oldBritghtness = Lighting.Ambient, Lighting.Brightness;

function functions.fullBright(toggle)
    if(not toggle) then
        maid.fullBright = nil;
        Lighting.Ambient, Lighting.Brightness = oldAmbient, oldBritghtness;
        return
    end;

    oldAmbient, oldBritghtness = Lighting.Ambient, Lighting.Brightness;
    maid.fullBright = Lighting:GetPropertyChangedSignal('Ambient'):Connect(function()
        Lighting.Ambient = Color3.fromRGB(255, 255, 255);
        Lighting.Brightness = library.flags.fullBrightValue;
    end);
    Lighting.Ambient = Color3.fromRGB(255, 255, 255);
end;

function functions.noBlur(t)
    Lighting.Blur.Enabled = not t;
end

do -- // Visuals
    VisualsMisc:AddToggle({
        text = 'Full Bright',
        callback = functions.fullBright
    })VisualsMisc:AddSlider({
        flag = 'Full Bright Value',
        textpos = 2,
        min = 0,
        max = 10,
        value = 1,
    });
end;
