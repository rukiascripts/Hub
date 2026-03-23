local Services = sharedRequire('utils/Services.lua');
local library = sharedRequire('UILibrary.lua');
local AltManagerAPI = sharedRequire('classes/AltManagerAPI.lua');
	local Players, GuiService, HttpService, StarterGui, VirtualInputManager = Services:Get('Players', 'GuiService', 'HttpService', 'StarterGui', 'VirtualInputManager');
	local LocalPlayer = Players.LocalPlayer;

	local BlockUtils = {};
	local IsFriendWith = LocalPlayer.IsFriendsWith;

	local apiAccount;

	task.spawn(function()
		--apiAccount = AltManagerAPI.new(LocalPlayer.Name);
	end);

	local function isFriendWith(userId)
		local suc, data = pcall(IsFriendWith, LocalPlayer, userId);

		if (suc) then
			return data;
		end;

		return true;
	end;

	local function findChild(parent, ...)
		local current = parent;
		for _, name in {...} do
			current = current and current:FindFirstChild(name);
		end;
		return current;
	end;

	local function clickAt(x, y, times)
		for _ = 1, (times or 3) do
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1);
			task.wait(0.05);
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1);
			task.wait(0.1);
		end;
	end;

	function BlockUtils:BlockUser(userId)
		if(library.flags.useAltManagerToBlock and apiAccount) then
			apiAccount:BlockUser(userId);

			local blockedListRetrieved, blockList = pcall(HttpService.JSONDecode, HttpService, apiAccount:GetBlockedList());
			if(blockedListRetrieved and typeof(blockList) == 'table' and blockList.success and blockList.total >= 20) then
				apiAccount:UnblockEveryone();
			end;
		else
			local playerToBlock = Instance.new('Player');
			playerToBlock.UserId = tonumber(userId);

			StarterGui:SetCore('PromptBlockPlayer', playerToBlock);
			task.wait(0.5);

			pcall(function()
				local buttons = findChild(
					game:GetService('CoreGui'),
					'FoundationOverlay', 'SafeAreaFrame', 'BlockingModalScreen',
					'BlockingModalContainerWrapper', 'BlockingModal', 'AlertModal',
					'AlertContents', 'Footer', 'Buttons'
				);
				if (not buttons) then return; end;

				local blockBtn;
				for _ = 1, 20 do
					blockBtn = buttons:FindFirstChild('3');
					if (blockBtn) then break; end;
					task.wait(0.25);
				end;
				if (not blockBtn) then return; end;

				local inset = GuiService:GetGuiInset();
				local pos = blockBtn.AbsolutePosition;
				local size = blockBtn.AbsoluteSize;
				clickAt(pos.X + size.X / 2, pos.Y + size.Y / 2 + inset.Y, 5);
			end);

			task.wait(0.5);
		end;
	end;

	function BlockUtils:UnblockUser()

	end;

	function BlockUtils:BlockRandomUser()
		for _, v in next, Players:GetPlayers() do
			if (v ~= LocalPlayer and not isFriendWith(v.UserId)) then
				self:BlockUser(v.UserId);
				break;
			end;
		end;
	end;

    return BlockUtils
