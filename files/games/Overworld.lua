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

local function teleportTo(position)
    local root = getRoot();
    if (not root) then return; end;
    enableNoclip();
    root.CFrame = CFrame.new(position);
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
    warn('[AutoFarm] Other player detected! Blocking and rejoining...');

    withFreeMouse(function()
        BlockUtils:BlockRandomUser();
    end);

    task.wait(1);
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

    teleportTo(primaryPart.Position);

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

local function startAntiRagdoll()
    if (maid.antiRagdoll) then return; end;
    maid.antiRagdoll = task.spawn(function()
        while (isRunning()) do
            pressKey(Enum.KeyCode.Space);
            task.wait(7);
        end;
    end);
end;

local function stopAntiRagdoll()
    maid.antiRagdoll = nil;
end;

local function startFarm()
    if (maid.farm) then return; end;

    if (library.flags.panicOnPlayerJoin) then
        startPlayerWatch();
    end;

    startAntiRagdoll();

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

local function stopFarm()
    stopAutoLockpick();
    stopPlayerWatch();
    stopAntiRagdoll();
    disableNoclip();
    releasePosition();
    maid.farm = nil;
end;

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

    teleportTo(anvilPart.Position);
    task.wait(0.5);
    if (not isOreFarming()) then return; end;

    fireproximityprompt(anvilPrompt);
    task.wait(1);
    if (not isOreFarming()) then return; end;

    local anvilUI = findChild(PlayerGui, 'ScreenGui', 'Frame', 'MidFrame', 'MaterialProcess', 'Anvil');
    if (not anvilUI) then
        warn('[OreFarm] Anvil UI not found');
        releasePosition();
        return;
    end;

    local pickaxeSlot = findPickaxeSlot();
    local repairSlot = findChild(anvilUI, 'Frame', 'Slots', 'Slot');
    if (not pickaxeSlot or not repairSlot) then
        warn('[OreFarm] Could not find pickaxe slot or repair slot');
        releasePosition();
        return;
    end;

    withFreeMouse(function()
        dragGui(pickaxeSlot, repairSlot);
    end);
    task.wait(0.5);
    if (not isOreFarming()) then return; end;

    local goldButton = findChild(anvilUI, 'ActionFrame', 'GoldButton');
    if (goldButton) then
        withFreeMouse(function()
            clickGui(goldButton, 3);
        end);
    end;
    task.wait(0.15);

    local repairButton = anvilUI:FindFirstChild('RepairButton');
    if (repairButton) then
        withFreeMouse(function()
            clickGui(repairButton, 3);
        end);
    end;

    task.wait(6);
    releasePosition();
    warn('[OreFarm] Repair complete');
end;

local function sellOreItems()
    warn('[OreFarm] Selling items...');

    local shopPart = findChild(workspace, 'Prox', 'ShopPart');
    if (not shopPart) then warn('[OreFarm] ShopPart not found'); return; end;

    local shopPrompt = findProximityPrompt(shopPart);
    local shopPartPos = shopPart:IsA('BasePart') and shopPart or shopPart:FindFirstChildWhichIsA('BasePart');
    if (not shopPartPos) then shopPartPos = shopPart; end;

    teleportTo(shopPartPos.Position);
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
    local HOTBAR_KEYCODES = {
        [1] = Enum.KeyCode.One, [2] = Enum.KeyCode.Two, [3] = Enum.KeyCode.Three,
        [4] = Enum.KeyCode.Four, [5] = Enum.KeyCode.Five, [6] = Enum.KeyCode.Six,
        [7] = Enum.KeyCode.Seven, [8] = Enum.KeyCode.Eight, [9] = Enum.KeyCode.Nine,
    };

    local pickaxe = char:FindFirstChild('Stone Pickaxe');
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
                if (char) then pickaxe = char:FindFirstChild('Stone Pickaxe'); end;
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

        local mineableRocks = {};
        for _, mesh in rockMound:GetDescendants() do
            if (mesh:IsA('MeshPart') and (mesh:GetAttribute('Mineable') or mesh.Name == 'Mineable Rock')) then
                table.insert(mineableRocks, mesh);
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
                pickaxe = char:FindFirstChild('Stone Pickaxe');
                if (not pickaxe) then return; end;
            end;

            teleportTo(rock.Position);
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

                task.wait(0.5);
            end;
        end;
    end;

    return true;
end;

local function startOreFarm()
    if (maid.oreFarm) then return; end;

    if (library.flags.panicOnPlayerJoin) then
        startPlayerWatch();
    end;

    startAntiRagdoll();

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

local function stopOreFarm()
    stopPlayerWatch();
    stopAntiRagdoll();
    disableNoclip();
    releasePosition();
    maid.oreFarm = nil;
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
    text = 'Only Pickup Gold',
    tip = 'Only loots Gold from containers, skips everything else',
});

farms:AddToggle({
    text = 'Auto Mine Ore',
    tip = 'Mines rocks in Green Biome, auto repairs pickaxe, sells loot, and rejoins when done.',
    callback = function(state: boolean): ()
        if (state) then
            startOreFarm();
        else
            stopOreFarm();
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
