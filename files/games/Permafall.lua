do -- // Automation Functions

    function functions.pickupItem(item, isSilver)
        if (not item) then return end;
        if (not item.Name:find('Dropped_')) then return end;
        
        local hasSilver = item:GetAttribute('Silver') and item:GetAttribute('Silver') ~= 0;
        
        -- If we're NOT looking for silver and the item HAS silver, skip it
        if (not isSilver and hasSilver) then return end;
        -- If we ARE looking for silver and the item DOESN'T have silver, skip it
        if (isSilver and not hasSilver) then return end;

        local touchInterest = item:FindFirstChildWhichIsA('TouchTransmitter');
        if (touchInterest) then 
            firetouchinterest(LocalPlayer.Character.HumanoidRootPart, item, 0); 
            task.wait(0.1);
            firetouchinterest(LocalPlayer.Character.HumanoidRootPart, item, 1);
        end;
    end;

    maid.newThrownChild = workspace.Thrown.ChildAdded:Connect(function(child)
        task.wait(0.05);
        
        local hasSilver = child:GetAttribute('Silver') and child:GetAttribute('Silver') ~= 0;
        
        -- Pick up silver items if silver toggle is on
        if (library.flags.autoPickupSilver and hasSilver) then
            functions.pickupItem(child, true);
        end;
        
        -- Pick up non-silver items if items toggle is on
        if (library.flags.autoPickupItems and not hasSilver) then
            functions.pickupItem(child, false);
        end;
    end);
end;

do -- // Automation
    automation:AddDivider('Pickup')

    automation:AddToggle({
        text = 'Auto Pickup Items',
        tip = 'Automatically picks up any items that get dropped.',
        callback = function(state)
            if (state) then
                for _, child in workspace.Thrown:GetChildren() do
                    local hasSilver = child:GetAttribute('Silver') and child:GetAttribute('Silver') ~= 0;
                    if (not hasSilver) then
                        functions.pickupItem(child, false);
                    end;
                end;
            end;
        end
    })

    automation:AddToggle({
        text = 'Auto Pickup Silver',
        tip = 'Automatically picks up any silver that get dropped. [WARNING: THEY HAVE LOGS FOR SILVER PICKUPS]',
        callback = function(state)
            if (state) then
                for _, child in workspace.Thrown:GetChildren() do
                    local hasSilver = child:GetAttribute('Silver') and child:GetAttribute('Silver') ~= 0;
                    if (hasSilver) then
                        functions.pickupItem(child, true);
                    end;
                end;
            end;
        end
    })
end;
