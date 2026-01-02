local library = sharedRequire('UILibrary.lua');

local column1, column2 = unpack(library.columns);

local functions = {};

local localCheats = column1:AddSection('Local Cheats');
local notifier = column1:AddSection('Notifier');
local playerMods = column1:AddSection('Player Mods');
local misc = column2:AddSection('Misc');
local visuals = column2:AddSection('Visuals');
local farms = column2:AddSection('Farms');
local inventoryViewer = column2:AddSection('Inventory Viewer');
