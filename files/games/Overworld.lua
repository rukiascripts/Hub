local library = sharedRequire('UILibrary.lua');
local Maid = sharedRequire('utils/Maid.lua');
local Services = sharedRequire('utils/Services.lua');
local BlockUtils = sharedRequire('utils/BlockUtils.lua');
local ToastNotif = sharedRequire('classes/ToastNotif.lua');
local ControlModule = sharedRequire('classes/ControlModule.lua');

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

local localCheats = column1:AddSection('Local Cheats');
local combat = column1:AddSection('Combat');
local farms = column2:AddSection('Farms');
local misc = column2:AddSection('Misc');

local CONTAINER_PATH = workspace:WaitForChild('Containers'):WaitForChild('Lumbertown');
local PLACE_ID = game.PlaceId;
local LANE_KEYS = { Lane1 = Enum.KeyCode.A, Lane2 = Enum.KeyCode.W, Lane3 = Enum.KeyCode.D };

local MAX_ORE_POSITIONS = {
	Vector3.new(1349.742431640625, 99.3039321899414, 478.6925354003906),
	Vector3.new(1331.814453125, 95.43844604492188, 454.12872314453125),
};

local KILL_AURA_COOLDOWN = 0.3;
local WEAPON_KEYWORDS = { 'Club', 'Mace', 'Sword' };
local HOTBAR_KEYCODES = {
    [1] = Enum.KeyCode.One, [2] = Enum.KeyCode.Two, [3] = Enum.KeyCode.Three,
    [4] = Enum.KeyCode.Four, [5] = Enum.KeyCode.Five, [6] = Enum.KeyCode.Six,
    [7] = Enum.KeyCode.Seven, [8] = Enum.KeyCode.Eight, [9] = Enum.KeyCode.Nine,
};

local lootedTimestamps = {};
local lastAuraHit = 0;

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

local function dragGui(fromGui, toGui)
    local inset = GuiService:GetGuiInset();
    local fromPos = fromGui.AbsolutePosition;
    local fromSize = fromGui.AbsoluteSize;
    local toPos = toGui.AbsolutePosition;
    local toSize = toGui.AbsoluteSize;

    local fx = fromPos.X + fromSize.X / 2;
    local fy = fromPos.Y + fromSize.Y / 2 + inset.Y;
    local tx = toPos.X + toSize.X / 2;
    local ty = toPos.Y + toSize.Y / 2 + inset.Y;

    -- Move mouse to source, hold
    mousemoveabs(fx, fy);
    task.wait(0.5);
    VirtualInputManager:SendMouseButtonEvent(fx, fy, 0, true, game, 1);
    task.wait(0.53);
    -- Move mouse to target
    mousemoveabs(tx, ty);
    task.wait(0.5);
    -- Release at target
    VirtualInputManager:SendMouseButtonEvent(tx, ty, 0, false, game, 1);
    task.wait(0.5);
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

local function teleportTo(position, noclip: boolean?)
    local root = getRoot();
    if (not root) then return; end;
    if (noclip) then
        enableNoclip();
        holdPosition();
    end;
    root.CFrame = CFrame.new(position);
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
        local ID    = tostring(v.id);
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

local isTeleporting = false;

local function panic()
    if (isTeleporting) then return; end;
    isTeleporting = true;

    if (getgenv().stopFarm) then
        getgenv().stopFarm();
    end;

    if (getgenv().stopOreFarm) then
        getgenv().stopOreFarm();
    end;

    warn('[AutoFarm] Other player detected! Blocking and matchmaking hop...');

    task.spawn(function()
        withFreeMouse(function()
            BlockUtils:BlockRandomUser();
        end);
    end);
   
    task.wait(3);

    local MAX_RETRIES = 5;
    for i = 1, MAX_RETRIES do
        local ok, err = pcall(TeleportService.Teleport, TeleportService, PLACE_ID, LocalPlayer);
        if (ok) then return; end;
        warn('[AutoFarm] Teleport failed: ' .. tostring(err) .. ' (attempt ' .. i .. '/' .. MAX_RETRIES .. ')');
        task.wait(5 + (i * 3));
    end;

    warn('[AutoFarm] All teleport attempts failed, resetting state.');
    isTeleporting = false;
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
    local slotsFolder = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Inventory', 'Frame', 'Backpack', 'Slots');
    if (not slotsFolder) then return false; end;

    for i = 1, 32 do
        local slot = slotsFolder:FindFirstChild(tostring(i));
        if (not slot or slot:GetAttribute('Populated') ~= true) then
            return false;
        end;
    end;

    return true;
end;

local function sellStolenItems()
    warn('[AutoFarm] Inventory full, selling stolen items...');

    local shadySam = findChild(workspace, 'Npc', 'IdleNPC', 'Shady Sam');
    if (not shadySam) then warn('[AutoFarm] Shady Sam not found'); return; end;

    local samPart = shadySam.PrimaryPart or shadySam:FindFirstChildWhichIsA('BasePart');
    local root = getRoot();
    if (not samPart or not root) then return; end;

    enableNoclip();
    root.CFrame = CFrame.new(samPart.Position + Vector3.new(0, 0, -5));
    holdPosition();
    task.wait(0.5);
    if (not isRunning()) then return; end;

    local clientEvents = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents');
    if (not clientEvents) then return; end;

    clientEvents:WaitForChild('OpenShop'):FireServer('Shady Sam');
    task.wait(1.5);
    if (not isRunning()) then return; end;

    local shopFrame = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Shop');
    if (not shopFrame or not shopFrame.Visible) then
        warn('[AutoFarm] Shop did not open, retrying...');
        clientEvents:WaitForChild('OpenShop'):FireServer('Shady Sam');
        task.wait(2);
        if (not isRunning()) then return; end;
        shopFrame = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Shop');
        if (not shopFrame or not shopFrame.Visible) then
            warn('[AutoFarm] Shop failed to open');
            return;
        end;
    end;

    withFreeMouse(function()
        local sellTab = findChild(shopFrame, 'Main', 'Tabs', 'Sell');
        if (sellTab) then
            task.wait(0.2);
            clickGui(sellTab, 5);
        end;
    end);
    task.wait(0.5);
    if (not isRunning()) then return; end;

    local shopSlots = findChild(shopFrame, 'Main', 'Content', 'SlotsUI', 'Shop', 'ShopSlots');
    if (shopSlots) then
        local transaction = {};
        for _, child in shopSlots:GetChildren() do
            if (not child:IsA('ImageButton')) then continue; end;

            local encoded = child:GetAttribute('ItemEncode');
            if (not encoded) then continue; end;

            local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
            if (ok and data.Ownership == 'Steal') then
                table.insert(transaction, { data.Name, data.Quantity, data.UID });
            end;
        end;

        if (#transaction > 0) then
            clientEvents:WaitForChild('ShopTransact'):InvokeServer({
                ShopId = 'Shady Sam',
                Type = 'Sell',
                transaction = transaction,
            });
        else
            warn('[AutoFarm] No stolen items to sell');
        end;
    end;

    task.wait(2);
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

local function isMaxOrePosition(rockMound)
    local pos = rockMound:GetPivot().Position;
    for _, target in MAX_ORE_POSITIONS do
        if ((pos - target).Magnitude < 5) then return true; end;
    end;
    return false;
end;

local function timedOut(startTime, duration)
    return ((os.clock() - startTime) >= duration);
end;

local function farmItem(model)
    if (not isRunning()) then return; end;
    local startTime = os.clock();
    local TIMEOUT = math.random(10, 15);

    if (isInventoryFull()) then sellStolenItems(); end;
    if (not isRunning()) then return; end;

    local prompt = findProximityPrompt(model);
    if (not prompt) then
        lootedTimestamps[model] = os.clock();
        return;
    end;

    local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA('BasePart');
    if (not primaryPart) then return; end;

    teleportTo(primaryPart.Position, true);

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

        while (isRunning() and model:GetAttribute('Locked')) do
            if (timedOut(startTime, TIMEOUT)) then
                warn('[AutoFarm] Lockpick timeout');
                stopAutoLockpick();
                releasePosition();
                lootedTimestamps[model] = os.clock();
                return;
            end;
            task.wait(0.2);
        end;
        stopAutoLockpick();
    end;

    task.wait(1);

    containerUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Container');
    if (not containerUI or not containerUI.Visible) then
        warn('[AutoFarm] Container UI not open, waiting... attempting to trigger prompt again');
        fireproximityprompt(prompt);
        while (isRunning()) do
            if (timedOut(startTime, TIMEOUT)) then
                warn('[AutoFarm] Container UI timeout');
                releasePosition();
                lootedTimestamps[model] = os.clock();
                return;
            end;

            task.wait(0.5);

            containerUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Container');

            if (containerUI and containerUI.Visible) then
                break;
            end;
        end;
    end;

    local moveItem = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents', 'MoveItem');
    local containerSlots = containerUI and findChild(containerUI, 'Container', 'Slots');
    if (moveItem and containerSlots) then
        local goldOnly = library.flags.onlyPickupGold;
        local backpackSlots = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Inventory', 'Frame', 'Backpack', 'Slots');

        local function findBackpackSlot(itemName)
            if (not backpackSlots) then return nil; end;
            local emptySlot = nil;
            for _, bpSlot in backpackSlots:GetChildren() do
                if (not bpSlot:IsA('ImageButton')) then continue; end;
                if (not bpSlot:GetAttribute('Populated')) then
                    if (not emptySlot) then emptySlot = tonumber(bpSlot.Name); end;
                    continue;
                end;
                local bpEncoded = bpSlot:GetAttribute('ItemEncode');
                if (not bpEncoded) then continue; end;
                local bpOk, bpData = pcall(HttpService.JSONDecode, HttpService, bpEncoded);
                if (bpOk and bpData.Name == itemName) then
                    return tonumber(bpSlot.Name);
                end;
            end;
            return emptySlot;
        end;

        local function isGold(itemName)
            return (string.find(itemName, 'Gold') ~= nil);
        end;

        for _, slot in containerSlots:GetChildren() do
            if (not slot:IsA('ImageButton') or not slot:GetAttribute('Populated')) then continue; end;

            local encoded = slot:GetAttribute('ItemEncode');
            if (not encoded) then continue; end;

            local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
            if (not ok or not data) then continue; end;

            if (goldOnly) then
                if (not isGold(data.Name)) then continue; end;
            else
                if (not isGold(data.Name) and data.Ownership ~= 'NPC') then continue; end;
            end;

            local fromIndex = tonumber(slot.Name);
            if (not fromIndex) then continue; end;

            local toIndex = findBackpackSlot(data.Name);
            if (not toIndex) then continue; end;

            moveItem:FireServer({
                FromIndex = fromIndex,
                FromData = 'Container',
                ToIndex = toIndex,
                ToData = 'Backpack',
                ItemInfo = {
                    Ownership = data.Ownership,
                    Quantity = data.Quantity,
                    Name = data.Name,
                    UID = data.UID,
                },
            });

            task.wait(0.15);
        end;
    else
        warn('[AutoFarm] Could not find container slots or MoveItem remote');
    end;

    releasePosition();

    lootedTimestamps[model] = os.clock();
end;

-- ── Auto Collect All Loot ──

local function collectAllLoot()
    local containerUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Container');
    if (not containerUI or not containerUI.Visible) then return; end;

    local moveItem = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents', 'MoveItem');
    local containerSlots = findChild(containerUI, 'Container', 'Slots');
    local backpackSlots = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Inventory', 'Frame', 'Backpack', 'Slots');
    if (not moveItem or not containerSlots or not backpackSlots) then return; end;

    local function findBackpackSlot(itemName)
        local emptySlot = nil;
        for _, bpSlot in backpackSlots:GetChildren() do
            if (not bpSlot:IsA('ImageButton')) then continue; end;
            if (not bpSlot:GetAttribute('Populated')) then
                if (not emptySlot) then emptySlot = tonumber(bpSlot.Name); end;
                continue;
            end;
            local encoded = bpSlot:GetAttribute('ItemEncode');
            if (not encoded) then continue; end;
            local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
            if (ok and data.Name == itemName) then
                return tonumber(bpSlot.Name);
            end;
        end;
        return emptySlot;
    end;

    for _, slot in containerSlots:GetChildren() do
        if (not slot:IsA('ImageButton') or not slot:GetAttribute('Populated')) then continue; end;

        local encoded = slot:GetAttribute('ItemEncode');
        if (not encoded) then continue; end;

        local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
        if (not ok or not data) then continue; end;

        local fromIndex = tonumber(slot.Name);
        if (not fromIndex) then continue; end;

        local toIndex = findBackpackSlot(data.Name);
        if (not toIndex) then continue; end;

        moveItem:FireServer({
            FromIndex = fromIndex,
            FromData = 'Container',
            ToIndex = toIndex,
            ToData = 'Backpack',
            ItemInfo = {
                Ownership = data.Ownership,
                Quantity = data.Quantity,
                Name = data.Name,
                UID = data.UID,
            },
        });

        task.wait(0.15);
    end;
end;

local function toggleAutoCollectLoot(toggle: boolean): ()
    if (not toggle) then
        maid.autoCollect = nil;
        return;
    end;

    if (maid.autoCollect) then return; end;

    local containerUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Container');

    if (containerUI) then
        maid.autoCollect = containerUI:GetPropertyChangedSignal('Visible'):Connect(function()
            if (containerUI.Visible and library.flags.autoCollectAllLoot) then
                task.wait(0.3);
                collectAllLoot();
            end;
        end);
    else
        -- container UI not loaded yet, poll for it
        maid.autoCollect = RunService.Heartbeat:Connect(function()
            if (not library.flags.autoCollectAllLoot) then return; end;
            local ui = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Container');
            if (not ui) then return; end;

            -- found it, switch to property listener
            maid.autoCollect = ui:GetPropertyChangedSignal('Visible'):Connect(function()
                if (ui.Visible and library.flags.autoCollectAllLoot) then
                    task.wait(0.3);
                    collectAllLoot();
                end;
            end);
        end);
    end;
end;

local function toggleAntiRagdoll(toggle: boolean): ()
    if (not toggle) then
        maid.antiRagdoll = nil;
        return;
    end;

    if (maid.antiRagdoll) then return; end;
    local enableRagdoll = findChild(ReplicatedStorage, 'RepStore_CORE', 'Events', 'EnableRagdoll');
    if (not enableRagdoll) then return; end;
    maid.antiRagdoll = task.spawn(function()
        while (library.flags.antiRagdoll) do
            enableRagdoll:FireServer(false);
            task.wait(1.5);
        end;
    end);
end;

local function toggleFarm(toggle: boolean): ()
    if (not toggle) then
        stopAutoLockpick();
        stopPlayerWatch();
        disableNoclip();
        releasePosition();
        maid.farm = nil;
        return;
    end;

    if (maid.farm) then return; end;

    if (library.flags.panicOnPlayerJoin) then
        startPlayerWatch();
    end;

    maid.farm = task.spawn(function()
        while (isRunning()) do
            local items = getValidItems();

            if (#items == 0) then
                warn('[AutoFarm] All loot collected, rejoining...');
                panic();
                return;
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

getgenv().stopFarm = function() toggleFarm(false); end;

-- ── Ore Farm ──

local function isOreFarming()
    return library.flags.autoMineOre;
end;

local function findPickaxeSlot()
    local hotbarSlots = findChild(PlayerGui, 'ScreenGui', 'Frame', 'Hotbar', 'Slots');
    if (not hotbarSlots) then return nil, nil; end;

    for _, slot in hotbarSlots:GetChildren() do
        if (not slot:IsA('ImageButton')) then continue; end;
        local encoded = slot:GetAttribute('ItemEncode');
        if (not encoded) then continue; end;
        local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
        if (ok and string.find(data.Name, 'Pickaxe')) then
            return slot, data;
        end;
    end;
    return nil, nil;
end;

local function needsRepair()
    local _, data = findPickaxeSlot();
    if (not data) then return false; end;
    return data.Durability and data.Durability <= 25;
end;

local function repairPickaxe()
    warn('[OreFarm] Repairing pickaxe...');

    local anvils = workspace:WaitForChild('Stations'):WaitForChild('Runtime');
    local anvilPart = nil;
    local anvilPrompt = nil;
    for _, child in anvils:GetChildren() do
        if (child.Name ~= 'Anvil') then continue; end;
        local prompt = findProximityPrompt(child);
        if (prompt) then
            anvilPart = child:IsA('BasePart') and child or child:FindFirstChildWhichIsA('BasePart');
            anvilPrompt = prompt;
            break;
        end;
    end;

    if (not anvilPart or not anvilPrompt) then
        warn('[OreFarm] No anvil found');
        return;
    end;

    teleportTo(anvilPart.Position, true);
    task.wait(1.5);
    fireproximityprompt(anvilPrompt);
    if (not isOreFarming()) then return; end;

    local _, data = findPickaxeSlot();
    if (not data) then return; end;

    local requestRepair = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents', 'RequestRepair');
    requestRepair:FireServer(
        data.UID, -- pickaxe id
        '2'-- repair type (1 = normal, 2 = gold)
    );


    -- fireproximityprompt(anvilPrompt);
    -- task.wait(1);
    -- if (not isOreFarming()) then return; end;

    -- local anvilUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'MaterialProcess', 'Anvil');
    -- if (not anvilUI) then
    --     warn('[OreFarm] Anvil UI not found');
    --     releasePosition();
    --     return;
    -- end;

    -- local pickaxeSlot = findPickaxeSlot();
    -- local repairSlot = findChild(anvilUI, 'Frame', 'Slots', 'Slot');
    -- if (not pickaxeSlot or not repairSlot) then
    --     warn('[OreFarm] Could not find pickaxe slot or repair slot');
    --     releasePosition();
    --     return;
    -- end;

    -- withFreeMouse(function()
    --     dragGui(pickaxeSlot, repairSlot);
    -- end);
    -- task.wait(0.5);
    -- if (not isOreFarming()) then return; end;

    -- local goldButton = findChild(anvilUI, 'ActionFrame', 'GoldButton');
    -- if (goldButton) then
    --     withFreeMouse(function()
    --         clickGui(goldButton, 3);
    --     end);
    -- end;
    -- task.wait(0.15);

    -- local repairButton = anvilUI:FindFirstChild('RepairButton');
    -- if (repairButton) then
    --     withFreeMouse(function()
    --         clickGui(repairButton, 3);
    --     end);
    -- end;

    task.wait(1.5);
    releasePosition();
    warn('[OreFarm] Repair complete');
end;

local function sellOreItems()
    warn('[OreFarm] Selling items...');

    local shopPart;
    for _, proxPart in workspace.Prox:GetChildren() do
        if (proxPart.Name ~= 'ShopPart') then continue; end;
        if (proxPart:GetAttribute('Id') == 'Max') then
            shopPart = proxPart;
            break;
        end;
    end;

    if (not shopPart) then warn('[OreFarm] ShopPart not found'); return; end;

    local shopPrompt = findProximityPrompt(shopPart);
    local shopPartPos = shopPart:IsA('BasePart') and shopPart or shopPart:FindFirstChildWhichIsA('BasePart');
    if (not shopPartPos) then shopPartPos = shopPart; end;

    teleportTo(shopPartPos.Position, true);
    task.wait(0.5);
    if (not isOreFarming()) then return; end;

    if (shopPrompt) then
        fireproximityprompt(shopPrompt);
    end;
    
    task.wait(1.5);
    if (not isOreFarming()) then return; end;

    local shopFrame = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'Shop');
    if (not shopFrame or not shopFrame.Visible) then
        warn('[OreFarm] Shop did not open');
        releasePosition();
        return;
    end;

    withFreeMouse(function()
        local sellTab = findChild(shopFrame, 'Main', 'Tabs', 'Sell');
        if (sellTab) then
            task.wait(0.2);
            clickGui(sellTab, 5);
        end;
    end);
    task.wait(0.5);
    if (not isOreFarming()) then return; end;

    local shopSlots = findChild(shopFrame, 'Main', 'Content', 'SlotsUI', 'Shop', 'ShopSlots');
    if (shopSlots) then
        local transaction = {};
        for _, child in shopSlots:GetChildren() do
            if (not child:IsA('ImageButton')) then continue; end;

            local encoded = child:GetAttribute('ItemEncode');
            if (not encoded) then continue; end;

            local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
            if (not ok) then continue; end;

            if (not string.find(data.Name, 'Pickaxe')) then
                table.insert(transaction, { data.Name, data.Quantity, data.UID });
            end;
        end;

        if (#transaction > 0) then
            local clientEvents = findChild(ReplicatedStorage, 'RepStore_CORE', 'ClientEvents');
            if (clientEvents) then
                clientEvents:WaitForChild('ShopTransact'):InvokeServer({
                    ShopId = 'Max',
                    Type = 'Sell',
                    transaction = transaction,
                });
            end;
        end;
    end;

    releasePosition();
    task.wait(1);
    warn('[OreFarm] Selling complete');
end;

local function mineAllRocks()
    local rocksFolder = workspace:WaitForChild('Mineable Rocks', 10);
    rocksFolder = rocksFolder and rocksFolder:WaitForChild('Green Biome', 10);
    if (not rocksFolder) then warn('[OreFarm] Rocks folder not found'); return false; end;

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait();

    local pickaxe = char:FindFirstChild('Stone Pickaxe') or char:FindFirstChild('Silver Pickaxe') or char:FindFirstChild('Iron Pickaxe');
    if (not pickaxe) then
        local slot = findPickaxeSlot();
        if (slot) then
            local slotNum = tonumber(slot.Name);
            local keyCode = slotNum and HOTBAR_KEYCODES[slotNum];
            if (keyCode) then
                warn('[OreFarm] Equipping pickaxe from hotbar slot ' .. slotNum);
                pressKey(keyCode);
                task.wait(1);
                char = LocalPlayer.Character;
                if (char) then pickaxe = char:FindFirstChild('Stone Pickaxe') or char:FindFirstChild('Silver Pickaxe') or char:FindFirstChild('Iron Pickaxe'); end;
            end;
        end;
        if (not pickaxe) then warn('[OreFarm] Pickaxe not found'); return false; end;
    end;

    local repCore = ReplicatedStorage:WaitForChild('RepStore_CORE', 10);
    local harvestTrigger = repCore and repCore:WaitForChild('Events', 10);
    harvestTrigger = harvestTrigger and harvestTrigger:WaitForChild('HarvestTrigger', 10);
    if (not harvestTrigger) then warn('[OreFarm] HarvestTrigger not found'); return false; end;

    for _, rockMound in rocksFolder:GetChildren() do
        if (not isOreFarming()) then return; end;
        if (rockMound.Name ~= 'Rock Mound') then continue; end;
        if (library.flags.onlyMaxsOre and not isMaxOrePosition(rockMound)) then continue; end;

        local mineableRocks = {};
         for _, mesh in rockMound:GetDescendants() do
            if (mesh:IsA('MeshPart') and (mesh:GetAttribute('Mineable') or mesh.Name == 'Mineable Rock')) then
                if (library.flags.onlyMineTin) then
                    if (mesh:FindFirstChild('Tin')) then
                        table.insert(mineableRocks, mesh);
                    end;
                else
                    table.insert(mineableRocks, mesh);
                end;
            end;
        end;

        warn('[OreFarm] Rock Mound has ' .. #mineableRocks .. ' mineable rocks');
        if (#mineableRocks == 0) then continue; end;

        for _, rock in mineableRocks do
            if (not isOreFarming()) then return; end;
            if (not rock.Parent or rock.Transparency == 1) then continue; end;

            if (isInventoryFull()) then
                sellOreItems();
                if (not isOreFarming()) then return; end;
            end;

            if (needsRepair()) then
                repairPickaxe();
                char = LocalPlayer.Character;
                if (not char) then return; end;
                pickaxe = char:FindFirstChild('Stone Pickaxe') or char:FindFirstChild('Silver Pickaxe') or char:FindFirstChild('Iron Pickaxe');
                if (not pickaxe) then return; end;
            end;

            teleportTo(rock.Position, true);
            task.wait(0.5);

            local mineStart = os.clock();
            while (isOreFarming() and (os.clock() - mineStart) < 15) do
                if (rock.Transparency == 1 or not rock.Parent) then break; end;
                if (needsRepair()) then break; end;

                for _, mesh in mineableRocks do
                    if (mesh.Parent and mesh.Transparency ~= 1) then
                        harvestTrigger:FireServer(mesh, pickaxe);
                    end;
                end;

                task.wait(0.1);
            end;
        end;
    end;

    return true;
end;

local function toggleOreFarm(toggle: boolean): ()
    if (not toggle) then
        stopPlayerWatch();
        disableNoclip();
        releasePosition();
        maid.oreFarm = nil;
        return;
    end;

    if (maid.oreFarm) then return; end;

    if (library.flags.panicOnPlayerJoin) then
        startPlayerWatch();
    end;

    maid.oreFarm = task.spawn(function()
        while (isOreFarming()) do
            local mined = mineAllRocks();
            if (not isOreFarming()) then break; end;

            if (not mined) then
                warn('[OreFarm] Mining failed, retrying in 5 seconds...');
                task.wait(5);
                continue;
            end;

            warn('[OreFarm] All rocks mined, selling before rejoin...');
            sellOreItems();
            if (not isOreFarming()) then break; end;

            if (needsRepair()) then
                repairPickaxe();
            end;

            warn('[OreFarm] All rocks mined, rejoining...');
            panic();
            return;
        end;
    end);
end;
getgenv().stopOreFarm = function() toggleOreFarm(false); end;

-- ── Goblin King Farm ──

local function isGoblinFarming()
    return library.flags.autoFarmGoblinKing;
end;

local function findCaveDoor()
    local entrances = findChild(workspace, 'Dungeon Entrances', 'Cave_Entrances');
    if (not entrances) then return nil; end;

    for _, dungeon in entrances:GetChildren() do
        local portal = findChild(dungeon, 'Portal');
        if (not portal) then continue; end;

        local door = dungeon:FindFirstChild('Door');
        local prompt = portal:FindFirstChild('TeleportPrompt');
        if (door and door:IsA('BasePart') and prompt and prompt:IsA('ProximityPrompt')) then
            return door, prompt;
        end;
    end;
    return nil;
end;

local function findGoblinKing(bossAssets)
    for _, child in bossAssets:GetChildren() do
        if (child.Name ~= 'Goblin King' or not child:IsA('Model')) then continue; end;
        local hum = child:FindFirstChildWhichIsA('Humanoid');
        if (hum and hum.Health > 0) then return child, hum; end;
    end;
    return nil;
end;

local function findGoblinKingLoot(bossAssets)
    for _, child in bossAssets:GetChildren() do
        if (child.Name ~= 'Goblin King') then continue; end;
        local prompt = findProximityPrompt(child);
        if (prompt) then
            local hum = child:FindFirstChildWhichIsA('Humanoid');
            if (not hum or hum.Health <= 0) then return child, prompt; end;
        end;
    end;
    return nil;
end;

local function getCurrentCave()
    local dungeonNodes = workspace:FindFirstChild('Dungeon Nodes');
    if (not dungeonNodes) then return nil; end;

    for _, cave in dungeonNodes:GetChildren() do
        if (cave:FindFirstChild('ExitPreset')) then return cave; end;
    end;
    return nil;
end;

local PROMPT_ATTEMPTS = 3;
local PROMPT_TIMEOUT = 10;

local function tryFirePromptAndWait(prompt, checkFn, label)
    for attempt = 1, PROMPT_ATTEMPTS do
        fireproximityprompt(prompt);
        local elapsed = 0;
        local waitPer = PROMPT_TIMEOUT / PROMPT_ATTEMPTS;
        while (elapsed < waitPer) do
            task.wait(1);
            elapsed += 1;
            if (checkFn()) then return true; end;
            if (not isGoblinFarming()) then return false; end;
        end;
        warn('[GoblinFarm] ' .. label .. ' attempt ' .. attempt .. '/' .. PROMPT_ATTEMPTS .. ' failed');
    end;
    return false;
end;

local goblinKingRoot = nil;

local function updateGoblinPosition()
    local root = getRoot();
    if (not root or not goblinKingRoot) then return; end;

    local yOffset = library.flags.goblinYOffset or -6;
    local zOffset = library.flags.goblinZOffset or 0;
    root.CFrame = CFrame.new(goblinKingRoot.Position + Vector3.new(0, yOffset, zOffset));
end;

local function toggleGoblinKingFarm(toggle: boolean): ()
    if (not toggle) then
        maid.goblinFarm = nil;
        goblinKingRoot = nil;
        disableNoclip();
        releasePosition();
        return;
    end;

    if (maid.goblinFarm) then return; end;

    if (library.flags.panicOnPlayerJoin) then
        startPlayerWatch();
    end;

    local hitPlayer = findChild(ReplicatedStorage, 'RepStore_CORE', 'Events', 'HitPlayer');
    if (not hitPlayer) then warn('[GoblinFarm] HitPlayer remote not found'); return; end;

    maid.goblinFarm = task.spawn(function()
        local dungeonsDone = 0;

        while (isGoblinFarming()) do
            -- Step 1: Enter a cave from the overworld
            local cave = getCurrentCave();
            if (not cave) then
                local door, prompt = findCaveDoor();
                if (not door or not prompt) then
                    warn('[GoblinFarm] No cave door found');
                    task.wait(2);
                    continue;
                end;

                teleportTo(door.Position);
                task.wait(0.5);
                if (not isGoblinFarming()) then break; end;

                local entered = tryFirePromptAndWait(prompt, function()
                    return getCurrentCave() ~= nil;
                end, 'Cave entrance');

                cave = getCurrentCave();
                if (not entered or not cave) then
                    warn('[GoblinFarm] Cave failed to load after ' .. PROMPT_ATTEMPTS .. ' attempts, skipping');
                    dungeonsDone += 1;
                    continue;
                end;
            end;

            if (not isGoblinFarming()) then break; end;

            -- Step 2: TP to StartNode
            local startNode = findChild(cave, 'ExitPreset', 'StartNode');
            if (startNode) then
                local startPart = startNode:IsA('BasePart') and startNode or startNode:FindFirstChildWhichIsA('BasePart');
                if (startPart) then
                    teleportTo(startPart.Position);
                    task.wait(0.5);
                end;
            end;

            if (not isGoblinFarming()) then break; end;

            -- Step 3: Check for Goblin King room
            local room = cave:FindFirstChild('GobKingRoomCaveGen');
            if (not room) then
                warn('[GoblinFarm] No Goblin King in ' .. cave.Name .. ', moving to next dungeon');
                local exitPortal = findChild(cave, 'ExitPreset', 'ExitPortal');
                if (exitPortal) then
                    local exitPart = exitPortal:IsA('BasePart') and exitPortal or exitPortal:FindFirstChildWhichIsA('BasePart');
                    local exitPrompt = findProximityPrompt(exitPortal);
                    if (exitPart and exitPrompt) then
                        teleportTo(exitPart.Position);
                        task.wait(0.5);
                        tryFirePromptAndWait(exitPrompt, function()
                            return getCurrentCave() ~= cave;
                        end, 'Exit portal');
                    end;
                end;

                dungeonsDone += 1;
                continue;
            end;

            -- Step 4: Find and kill the Goblin King
            local bossAssets = room:FindFirstChild('BossAssets');
            if (not bossAssets) then
                warn('[GoblinFarm] BossAssets not found');
                task.wait(2);
                continue;
            end;

            local king, hum = findGoblinKing(bossAssets);
            if (king and hum) then
                goblinKingRoot = king.PrimaryPart or king:FindFirstChild('HumanoidRootPart');
                if (goblinKingRoot) then
                    updateGoblinPosition();
                    holdPosition();
                    enableNoclip();
                    task.wait(0.3);
                end;

                local selectedWeapon = library.flags.killAuraWeapon or 'Fist';
                local weapon;
                if (selectedWeapon == 'Fist') then
                    weapon = 'Punch';
                else
                    weapon = getEquippedWeapon();
                end;

                while (isGoblinFarming() and hum.Health > 0) do
                    if (weapon) then
                        hitPlayer:FireServer(king, weapon);
                    end;
                    task.wait(KILL_AURA_COOLDOWN);
                end;

                goblinKingRoot = nil;
                disableNoclip();
                releasePosition();

                if (not isGoblinFarming()) then break; end;
                task.wait(1);
            end;

            -- Step 5: Loot the Goblin King
            local lootModel, lootPrompt = findGoblinKingLoot(bossAssets);
            if (lootModel and lootPrompt) then
                local lootPart = lootModel.PrimaryPart or lootModel:FindFirstChildWhichIsA('BasePart');
                if (lootPart) then
                    teleportTo(lootPart.Position);
                    task.wait(0.5);
                end;
                fireproximityprompt(lootPrompt);
                task.wait(1);
                collectAllLoot();
                task.wait(0.5);
            end;

            dungeonsDone += 1;

            -- Step 6: Exit to next dungeon
            local exitPortal = findChild(cave, 'ExitPreset', 'ExitPortal');
            if (exitPortal) then
                local exitPart = exitPortal:IsA('BasePart') and exitPortal or exitPortal:FindFirstChildWhichIsA('BasePart');
                local exitPrompt = findProximityPrompt(exitPortal);
                if (exitPart and exitPrompt) then
                    teleportTo(exitPart.Position);
                    task.wait(0.5);
                    tryFirePromptAndWait(exitPrompt, function()
                        return getCurrentCave() ~= cave;
                    end, 'Exit portal');
                end;
            end;

            -- Step 7: Check if all dungeons cleared, rejoin to refresh
            local entrances = findChild(workspace, 'Dungeon Entrances', 'Cave_Entrances');
            local totalDungeons = entrances and #entrances:GetChildren() or 0;

            if (dungeonsDone >= totalDungeons) then
                warn('[GoblinFarm] All ' .. dungeonsDone .. ' dungeons cleared, rejoining to refresh...');
                task.wait(1);
                pcall(TeleportService.Teleport, TeleportService, PLACE_ID, LocalPlayer);
                break;
            end;
        end;
    end);
end;

-- ── Kill Aura ──

local function isWeapon(name: string): boolean
    for _, keyword in WEAPON_KEYWORDS do
        if (string.find(name, keyword)) then return true; end;
    end;
    return false;
end;

local function getEquippedWeapon()
    local char = LocalPlayer.Character;
    if (not char) then return nil; end;

    for _, child in char:GetChildren() do
        if (child:IsA('Tool')) then return child.Name; end;
    end;

    -- no weapon equipped, try to find one in hotbar and equip it
    local hotbarSlots = findChild(PlayerGui, 'ScreenGui', 'Frame', 'Hotbar', 'Slots');
    if (not hotbarSlots) then return nil; end;

    for _, slot in hotbarSlots:GetChildren() do
        if (not slot:IsA('ImageButton')) then continue; end;
        local encoded = slot:GetAttribute('ItemEncode');
        if (not encoded) then continue; end;
        local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded);
        if (not ok or not isWeapon(data.Name)) then continue; end;

        local slotNum = tonumber(slot.Name);
        local keyCode = slotNum and HOTBAR_KEYCODES[slotNum];
        if (keyCode) then
            pressKey(keyCode);
            task.wait(0.3);
            return data.Name;
        end;
    end;

    return nil;
end;

local function getNearbyEnemies(range: number)
    local root = getRoot();
    if (not root) then return {}; end;

    local enemies = {};
    for _, child in workspace:GetDescendants() do
        if (not child:IsA('Humanoid') or child.Health <= 0) then continue; end;

        local model = child.Parent;
        if (not model or not model:IsA('Model')) then continue; end;

        local player = Players:GetPlayerFromCharacter(model);
        if (player) then continue; end;

        local enemyRoot = model.PrimaryPart or model:FindFirstChild('HumanoidRootPart');
        if (not enemyRoot) then continue; end;

        local dist = (enemyRoot.Position - root.Position).Magnitude;
        if (dist <= range) then
            table.insert(enemies, model);
        end;
    end;
    return enemies;
end;

local function toggleKillAura(toggle: boolean): ()
    if (not toggle) then
        maid.killAura = nil;
        return;
    end;

    if (maid.killAura) then return; end;

    local hitPlayer = findChild(ReplicatedStorage, 'RepStore_CORE', 'Events', 'HitPlayer');
    if (not hitPlayer) then warn('[KillAura] HitPlayer remote not found'); return; end;

    maid.killAura = RunService.Heartbeat:Connect(function()
        if (not library.flags.killAura) then return; end;

        local now = DateTime.now().UnixTimestampMillis / 1000;
        if ((now - lastAuraHit) < KILL_AURA_COOLDOWN) then return; end;

        local selectedWeapon = library.flags.killAuraWeapon or 'Fist';
        local weapon;
        if (selectedWeapon == 'Fist') then
            weapon = 'Punch';
        else
            weapon = getEquippedWeapon();
            if (not weapon) then return; end;
        end;

        local enemies = getNearbyEnemies(library.flags.killAuraRange or 30);
        for _, enemy in enemies do
            hitPlayer:FireServer(enemy, weapon);
        end;

        lastAuraHit = now;
    end);
end;

-- ── Local Cheats ──

local function startSpeedHack(toggle: boolean): ()
    if (not toggle) then
        maid.speedHack = nil;
        maid.speedHackBv = nil;
        return;
    end;

    maid.speedHack = RunService.Heartbeat:Connect(function()
        local root = getRoot();
        local char = LocalPlayer.Character;
        if (not root or not char) then return; end;

        local humanoid = char:FindFirstChildWhichIsA('Humanoid');
        if (not humanoid) then return; end;

        if (library.flags.fly) then
            maid.speedHackBv = nil;
            return;
        end;

        maid.speedHackBv = maid.speedHackBv or Instance.new('BodyVelocity');
        maid.speedHackBv.MaxForce = Vector3.new(100000, 0, 100000);
        maid.speedHackBv.Parent = root;
        maid.speedHackBv.Velocity = humanoid.MoveDirection * library.flags.speedHackValue;
    end);
end;

local function startFly(toggle: boolean): ()
    if (not toggle) then
        maid.flyHack = nil;
        maid.flyBv = nil;
        return;
    end;

    maid.flyBv = Instance.new('BodyVelocity');
    maid.flyBv.MaxForce = Vector3.new(math.huge, math.huge, math.huge);

    maid.flyHack = RunService.Heartbeat:Connect(function()
        local root = getRoot();
        local camera = workspace.CurrentCamera;
        if (not root or not camera) then return; end;

        maid.flyBv.Parent = root;
        maid.flyBv.Velocity = camera.CFrame:VectorToWorldSpace(ControlModule:GetMoveVector() * library.flags.flyHackValue);
    end);
end;

local function startInfiniteJump(toggle: boolean): ()
    if (not toggle) then return; end;

    repeat
        local root = getRoot();
        if (root and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
            root.Velocity = Vector3.new(root.Velocity.X, library.flags.infiniteJumpHeight, root.Velocity.Z);
        end;
        task.wait(0.1);
    until not library.flags.infiniteJump;
end;

local function startNoclipToggle(toggle: boolean): ()
    if (not toggle) then
        disableNoclip();
        return;
    end;
    enableNoclip();
end;

local function goToGround(): ()
    local root = getRoot();
    if (not root) then return; end;

    local params = RaycastParams.new();
    params.FilterDescendantsInstances = { LocalPlayer.Character };
    params.FilterType = Enum.RaycastFilterType.Exclude;

    local result = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), params);
    if (not result) then return; end;

    root.CFrame *= CFrame.new(0, -(root.Position.Y - result.Position.Y) + 3, 0);
    root.Velocity *= Vector3.new(1, 0, 1);
end;

-- ── UI ──

localCheats:AddToggle({
    text = 'Fly',
    callback = startFly
});

localCheats:AddSlider({
    min = 16,
    max = 250,
    flag = 'Fly Hack Value',
    textpos = 2
});

localCheats:AddToggle({
    text = 'Speedhack',
    callback = startSpeedHack
});

localCheats:AddSlider({
    min = 16,
    max = 250,
    flag = 'Speed Hack Value',
    textpos = 2
});

localCheats:AddToggle({
    text = 'Infinite Jump',
    callback = startInfiniteJump
});

localCheats:AddSlider({
    min = 50,
    max = 250,
    flag = 'Infinite Jump Height',
    textpos = 2
});

localCheats:AddToggle({
    text = 'No Clip',
    callback = startNoclipToggle
});

localCheats:AddToggle({
    text = 'Anti Ragdoll',
    tip = 'Prevents you from getting ragdolled',
    callback = toggleAntiRagdoll
});

localCheats:AddBind({ text = 'Go To Ground', callback = goToGround, mode = 'hold', nomouse = true });

combat:AddToggle({
    text = 'Kill Aura',
    tip = 'Attacks all nearby enemies with your equipped weapon',
    callback = toggleKillAura
});

combat:AddList({
    text = 'Kill Aura Weapon',
    flag = 'Kill Aura Weapon',
    values = {'Mace', 'Sword', 'Club', 'Fist'},
    value = 'Fist'
});

combat:AddSlider({
    min = 15,
    max = 100,
    flag = 'Kill Aura Range',
    textpos = 2
});

farms:AddToggle({
    text = 'Auto Farm Lumbertown',
    tip = 'Automatically farms containers in Lumbertown. Lockpicks, loots, and sells stolen items.',
    callback = toggleFarm
});

farms:AddToggle({
    text = 'Only Pickup Gold',
    tip = 'Only loots Gold from containers, skips everything else',
});

farms:AddToggle({
    text = 'Auto Collect All Loot',
    tip = 'Automatically collects all loot when a bag/container is opened',
    callback = toggleAutoCollectLoot
});

farms:AddDivider('Mining');

farms:AddToggle({
    text = 'Auto Mine Ore',
    tip = 'Mines rocks in Green Biome, auto repairs pickaxe, sells loot, and rejoins when done.',
    callback = toggleOreFarm
});

farms:AddToggle({
    text = 'Only Mine Tin',
    tip = 'Only mines Tin rocks, skips everything else',
});

farms:AddToggle({
    text = 'Only Max\'s Ore',
    flag = 'only maxs ore',
    tip = 'Only mines RockMounds in Max\'s area, rejoins when both are depleted',
});

farms:AddDivider('Combat');

farms:AddToggle({
    text = 'Auto Farm Goblin King',
    tip = 'Farms the Goblin King, auto repairs weapon',
    callback = toggleGoblinKingFarm
});

farms:AddSlider({
    text = 'Boss Up/Down Offset',
    min = -20,
    max = 20,
    default = -6,
    flag = 'Goblin Y Offset',
    textpos = 2,
    callback = updateGoblinPosition
});

farms:AddSlider({
    text = 'Boss Front/Back Offset',
    min = -20,
    max = 20,
    default = 0,
    flag = 'Goblin Z Offset',
    textpos = 2,
    callback = updateGoblinPosition
});

misc:AddToggle({
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

misc:AddButton({
    text = 'Teleport to Quest Marker',
    tip = 'Teleports you to the active quest marker',
    callback = function()
        local questPart = workspace:FindFirstChild('QuestPart');
        if (not questPart) then
            ToastNotif.new('No quest marker found');
            return;
        end;
        local pos = questPart:IsA('BasePart') and questPart.Position or questPart:GetPivot().Position;
        teleportTo(pos);
    end
});

misc:AddButton({
    text = 'Teleport to Anvil',
    tip = 'Teleports you to Max\'s anvil',
    callback = function()
        local anvils = findChild(workspace, 'Stations', 'Runtime');
        if (not anvils) then ToastNotif.new('Anvil not found'); return; end;

        for _, child in anvils:GetChildren() do
            if (child.Name ~= 'Anvil') then continue; end;
            local part = child:IsA('BasePart') and child or child:FindFirstChildWhichIsA('BasePart');
            if (part) then
                teleportTo(part.Position);
                return;
            end;
        end;

        ToastNotif.new('Anvil not found');
    end
});

task.delay(5, function()
    library:Close();
end);
