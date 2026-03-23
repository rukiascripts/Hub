local library = sharedRequire('UILibrary.lua');
local Maid = sharedRequire('utils/Maid.lua');
local Services = sharedRequire('utils/Services.lua');
local BlockUtils = sharedRequire('utils/BlockUtils.lua');
local ToastNotif = sharedRequire('classes/ToastNotif.lua');

local Players, RunService, UserInputService, HttpService, TweenService, VirtualInputManager, TeleportService, ReplicatedStorage, GuiService = Services:Get(
    'Players', 'RunService', 'UserInputService', 'HttpService', 'TweenService',
    'VirtualInputManager', 'TeleportService', 'ReplicatedStorage', 'GuiService'
);

Players = cloneref(Players);
RunService = cloneref(RunService);
UserInputService = cloneref(UserInputService);
ReplicatedStorage = cloneref(ReplicatedStorage);
TeleportService = cloneref(TeleportService);
VirtualInputManager = cloneref(VirtualInputManager);
GuiService = cloneref(GuiService);

local LocalPlayer = Players.LocalPlayer;
local PlayerGui = LocalPlayer:WaitForChild('PlayerGui');
local maid = Maid.new();

local column1, column2 = unpack(library.columns);

local farms = column1:AddSection('Farms');
local misc = column2:AddSection('Misc');

local CONTAINER_PATH = workspace:WaitForChild('Containers'):WaitForChild('Lumbertown');
local PLACE_ID = game.PlaceId;
local LANE_KEYS = { Lane1 = Enum.KeyCode.A, Lane2 = Enum.KeyCode.W, Lane3 = Enum.KeyCode.D };

local lootedTimestamps = {};

-- ── Helpers ──

local function isRunning()
    return library.flags.autoFarmLumbertown;
end;

local function getRoot()
    local char = LocalPlayer.Character;
    return char and char:FindFirstChild('HumanoidRootPart');
end;

local function clickAt(x, y, times)
    for _ = 1, (times or 3) do
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1);
        task.wait(0.05);
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1);
        task.wait(0.1);
    end;
end;

local function clickGui(guiButton, times)
    local inset = GuiService:GetGuiInset();
    local pos = guiButton.AbsolutePosition;
    local size = guiButton.AbsoluteSize;
    clickAt(pos.X + size.X / 2, pos.Y + size.Y / 2 + inset.Y, times);
end;

local function pressKey(keyCode)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game);
    task.delay(0.05, function()
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game);
    end);
end;

local function findChild(parent, ...)
    local current = parent;
    for _, name in {...} do
        current = current and current:FindFirstChild(name);
    end;
    return current;
end;

-- ── Mouse Unlock ──

local function withFreeMouse(callback)
    local conn = RunService.RenderStepped:Connect(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default;
    end);
    task.wait();
    callback();
    conn:Disconnect();
end;

-- ── Noclip & Position Hold ──

local function enableNoclip()
    if (maid.noclip) then return; end;
    maid.noclip = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character;
        if (not char) then return; end;
        for _, part in char:GetDescendants() do
            if (part:IsA('BasePart')) then
                part.CanCollide = false;
            end;
        end;
    end);
end;

local function disableNoclip()
    maid.noclip = nil;
end;

local function holdPosition()
    local root = getRoot();
    if (not root) then return; end;
    maid.holdBv = nil;
    local bv = Instance.new('BodyVelocity');
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge);
    bv.Velocity = Vector3.zero;
    bv.Parent = root;
    maid.holdBv = bv;
end;

local function releasePosition()
    maid.holdBv = nil;
end;

local function teleportTo(position, prompt)
    local root = getRoot();
    if (not root) then return; end;
    local offset = prompt and (prompt.MaxActivationDistance - 1) or 15;
    enableNoclip();
    root.CFrame = CFrame.new(position + Vector3.new(0, -offset, 0));
    holdPosition();
end;

-- ── Server Hop ──

local AllIDs = {};
local foundAnything = '';
local actualHour = os.date('!*t').hour;

pcall(function()
    AllIDs = HttpService:JSONDecode(readfile('server-hop-temp.json'));
end);

if (#AllIDs == 0) then
    table.insert(AllIDs, actualHour);
    pcall(function() writefile('server-hop-temp.json', HttpService:JSONEncode(AllIDs)); end);
end;

local function serverHop()
    local cursor = foundAnything ~= '' and ('&cursor=' .. foundAnything) or '';
    local url = 'https://games.roblox.com/v1/games/' .. PLACE_ID .. '/servers/Public?sortOrder=Asc&limit=100' .. cursor;
    local site = HttpService:JSONDecode(game:HttpGet(url));

    if (site.nextPageCursor and site.nextPageCursor ~= 'null') then
        foundAnything = site.nextPageCursor;
    end;

    local num = 0;
    for _, v in site.data do
        local ID = tostring(v.id);
        local possible = true;

        if (tonumber(v.maxPlayers) > tonumber(v.playing)) then
            for _, existing in AllIDs do
                if (num == 0 and tonumber(actualHour) ~= tonumber(existing)) then
                    pcall(function() delfile('server-hop-temp.json'); end);
                    AllIDs = { actualHour };
                elseif (num ~= 0 and ID == tostring(existing)) then
                    possible = false;
                end;
                num += 1;
            end;

            if (possible) then
                table.insert(AllIDs, ID);
                pcall(function() writefile('server-hop-temp.json', HttpService:JSONEncode(AllIDs)); end);
                task.wait();
                pcall(TeleportService.TeleportToPlaceInstance, TeleportService, PLACE_ID, ID, LocalPlayer);
                task.wait(4);
            end;
        end;
    end;
end;

-- ── Panic ──

local function panic()
    warn('[AutoFarm] Other player detected! Blocking and server hopping...');

    withFreeMouse(function()
        BlockUtils:BlockRandomUser();
    end);

    task.wait(1);

    local ok = pcall(serverHop);
    if (not ok) then
        warn('[AutoFarm] Server hop failed, using fallback teleport');
    end;

    task.wait(2);
    TeleportService:Teleport(PLACE_ID);
end;

-- ── Player Watch ──

local function startPlayerWatch()
    if (maid.playerWatch) then return; end;
    if (#Players:GetPlayers() > 1) then panic(); return; end;
    maid.playerWatch = Players.PlayerAdded:Connect(function()
        if (#Players:GetPlayers() > 1) then panic(); end;
    end);
end;

local function stopPlayerWatch()
    maid.playerWatch = nil;
end;

-- ── AutoLockpick ──

local function isNoteOverlapping(note, imageButton)
    local notePos = note.AbsolutePosition.Y + note.AbsoluteSize.Y / 2;
    local btnTop = imageButton.AbsolutePosition.Y;
    return notePos >= btnTop and notePos <= btnTop + imageButton.AbsoluteSize.Y;
end;

local function stopAutoLockpick()
    maid.lockpick = nil;
end;

local function startAutoLockpick()
    local lockPickGui = PlayerGui:FindFirstChild('LockPicking') or PlayerGui:WaitForChild('LockPicking', 5);
    if (not lockPickGui) then return; end;

    local mainFrame = lockPickGui:FindFirstChild('MainFrame');
    if (not mainFrame) then return; end;

    stopAutoLockpick();

    maid.lockpick = RunService.Heartbeat:Connect(function()
        if (not isRunning() or not lockPickGui.Parent) then
            stopAutoLockpick();
            return;
        end;
        if (not mainFrame.Visible) then return; end;

        for laneName, keyCode in LANE_KEYS do
            local lane = mainFrame:FindFirstChild(laneName);
            if (not lane) then continue; end;

            local imageButton = lane:FindFirstChild('ImageButton');
            if (not imageButton) then continue; end;

            for _, child in lane:GetChildren() do
                if (child.Name == 'Note' and isNoteOverlapping(child, imageButton)) then
                    pressKey(keyCode);
                    break;
                end;
            end;
        end;
    end);
end;

local function startLockpicking()
    local lockPickGui = PlayerGui:FindFirstChild('LockPicking') or PlayerGui:WaitForChild('LockPicking', 5);
    if (not lockPickGui) then return; end;

    local textButton = findChild(lockPickGui, 'MainFrame', 'Controls', 'StartButton', 'TextButton');
    if (textButton) then
        task.wait(0.3);
        clickGui(textButton, 3);
    end;

    startAutoLockpick();
end;

-- ── Inventory & Selling ──

local function isInventoryFull()
    local slot32 = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Inventory', 'Frame', 'Backpack', 'Slots', '32');
    return slot32 and slot32:GetAttribute('Populated') == true;
end;

local function sellStolenItems()
    warn('[AutoFarm] Inventory full, selling stolen items...');

    local shadySam = findChild(workspace, 'Npc', 'IdleNPC', 'Shady Sam');
    if (not shadySam) then warn('[AutoFarm] Shady Sam not found'); return; end;

    local samPart = shadySam.PrimaryPart or shadySam:FindFirstChildWhichIsA('BasePart');
    local root = getRoot();
    if (not samPart or not root) then return; end;

    enableNoclip();
    root.CFrame = CFrame.new(samPart.Position);
    holdPosition();
    task.wait(0.25);
    if (not isRunning()) then return; end;

    local clientEvents = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents');
    if (not clientEvents) then return; end;

    clientEvents:WaitForChild('OpenShop'):FireServer('Shady Sam');
    task.wait(1);
    if (not isRunning()) then return; end;

    local sellTab = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Shop', 'Main', 'Tabs', 'Sell');
    if (sellTab) then clickGui(sellTab, 3); end;
    task.wait(0.25);
    if (not isRunning()) then return; end;

    local shopSlots = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Shop', 'Main', 'Content', 'SlotsUI', 'Shop', 'ShopSlots');
    if (shopSlots) then
        for _, child in shopSlots:GetChildren() do
            if (not isRunning()) then return; end;
            if (not child:IsA('ImageButton')) then continue; end;

            for _, attribute in child:GetAttributes() do
                if (typeof(attribute) == 'boolean' or attribute == 'Inventory' or attribute == 'Shop') then continue; end;

                local ok, data = pcall(HttpService.JSONDecode, HttpService, attribute);
                if (ok and data.Ownership == 'Steal') then
                    clientEvents:WaitForChild('ShopTransact'):InvokeServer({
                        ShopId = 'Shady Sam',
                        Type = 'Sell',
                        transaction = { { data.Name, data.Quantity, data.UID } }
                    });
                end;
            end;
        end;
    end;

    task.wait(9);
    warn('[AutoFarm] Selling complete, resuming farm');
end;

-- ── AutoFarm Core ──

local function getValidItems()
    local items = {};
    for _, child in CONTAINER_PATH:GetChildren() do
        if (not child:IsA('Model') or not child:GetAttribute('DropTable')) then continue; end;

        local restockVal = child:FindFirstChild('RestockTime');
        local restockDuration = restockVal and restockVal.Value or 60;
        local lastLooted = lootedTimestamps[child];

        if (not lastLooted or (os.clock() - lastLooted) >= restockDuration) then
            table.insert(items, child);
        end;
    end;
    return items;
end;

local function findProximityPrompt(model)
    for _, desc in model:GetDescendants() do
        if (desc:IsA('ProximityPrompt')) then return desc; end;
    end;
    return nil;
end;

local function farmItem(model)
    if (not isRunning()) then return; end;

    if (isInventoryFull()) then sellStolenItems(); end;
    if (not isRunning()) then return; end;

    local prompt = findProximityPrompt(model);
    if (not prompt) then
        lootedTimestamps[model] = os.clock();
        return;
    end;

    local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA('BasePart');
    if (not primaryPart) then return; end;

    teleportTo(primaryPart.Position, prompt);
    task.wait(0.5);
    if (not isRunning()) then return; end;

    local isLocked = model:GetAttribute('Locked');
    fireproximityprompt(prompt);
    task.wait(0.5);
    if (not isRunning()) then return; end;

    local containerUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Container');

    if (isLocked and model:GetAttribute('Locked')) then
        if (containerUI and containerUI.Visible) then
            lootedTimestamps[model] = os.clock();
            return;
        end;

        startLockpicking();
        while (isRunning() and model:GetAttribute('Locked')) do task.wait(0.2); end;
        stopAutoLockpick();
    end;

    task.wait(1);
    local moveItem = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents', 'MoveItem');
    if (moveItem) then
        moveItem:FireServer({ FromIndex = 'ALL', FromData = 'Container' });
    end;

    releasePosition();

    lootedTimestamps[model] = os.clock();
end;

local function startFarm()
    if (maid.farm) then return; end;

    if (library.flags.panicOnPlayerJoin) then
        startPlayerWatch();
    end;

    maid.farm = task.spawn(function()
        while (isRunning()) do
            local items = getValidItems();

            if (#items == 0) then
                task.wait(1);
                continue;
            end;

            for _, item in items do
                if (not isRunning()) then break; end;
                farmItem(item);
                task.wait(0.5);
            end;

            task.wait(1);
        end;
    end);
end;

local function stopFarm()
    stopAutoLockpick();
    stopPlayerWatch();
    disableNoclip();
    releasePosition();
    maid.farm = nil;
end;

-- ── UI ──

farms:AddToggle({
    text = 'Auto Farm Lumbertown',
    tip = 'Automatically farms containers in Lumbertown. Lockpicks, loots, and sells stolen items.',
    callback = function(state: boolean): ()
        if (state) then
            startFarm();
        else
            stopFarm();
        end;
    end
});

farms:AddToggle({
    text = 'Panic on Player Join',
    tip = 'Blocks a random player and server hops when someone joins',
    callback = function(state: boolean): ()
        if (state) then
            startPlayerWatch();
        else
            stopPlayerWatch();
        end;
    end
});

misc:AddButton({
    text = 'Server Hop',
    tip = 'Jumps to another server',
    callback = function()
        if (library:ShowConfirm('Are you sure you want to switch server?')) then
            withFreeMouse(function()
                BlockUtils:BlockRandomUser();
            end);
            local ok = pcall(serverHop);
            if (not ok) then
                TeleportService:Teleport(PLACE_ID);
            end;
        end;
    end
});
