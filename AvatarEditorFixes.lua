-- ============================================
-- FIXES FOR ROBLOX AVATAR EDITOR ERRORS
-- ============================================
-- This file contains fixes for two common Avatar Editor errors:
-- 1. "attempt to index nil with 'AddScale'" error
-- 2. "PromptSetFavorite can not be called again while currently in progress" error
-- ============================================

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============================================
-- FIX 1: AddScale Nil Indexing Error
-- ============================================
-- Problem: ParentObj.TextLabel or ParentObj.Outer is nil when AddScale is called
-- Solution: Add proper nil checks and WaitForChild before accessing properties

-- Example of FIXED AddScale usage in your code:
--[[
ORIGINAL (BROKEN):
    local toggle = Library:AddToggle("MyToggle", {Text = "Enable Feature"})
    toggle:AddScale("ScaleId", {Default = 1, Min = 0.1, Max = 5})

FIXED VERSION:
]]

function SafeAddScale(parentObj, id, info)
    -- Validate parent object exists
    if not parentObj then
        warn("[AddScale] Parent object is nil!")
        return nil
    end
    
    -- Validate required fields
    if not info or not info.Default or not info.Min or not info.Max then
        warn("[AddScale] Missing required fields (Default, Min, Max)")
        return nil
    end
    
    -- Ensure parent has valid container (TextLabel or Outer)
    local parentContainer = parentObj.TextLabel or parentObj.Outer
    
    if not parentContainer then
        warn("[AddScale] Parent object has no TextLabel or Outer property!")
        return nil
    end
    
    -- If parentContainer is a string name instead of instance, try to find it
    if typeof(parentContainer) == "string" then
        warn("[AddScale] Parent container is a string, attempting to resolve...")
        -- You may need to adjust this based on your specific structure
        parentContainer = nil
    end
    
    -- Proceed with AddScale only if validation passed
    if parentContainer then
        return parentObj:AddScale(id, info)
    end
    
    return nil
end

-- Usage example in your existing code:
--[[
-- Instead of directly calling:
-- myToggle:AddScale("scale1", {Default = 1, Min = 0.1, Max = 5, Callback = function(v) end})

-- Use the safe wrapper:
SafeAddScale(myToggle, "scale1", {Default = 1, Min = 0.1, Max = 5, Callback = function(v) end})
]]

-- ============================================
-- FIX 2: PromptSetFavorite Debounce System
-- ============================================
-- Problem: PromptSetFavorite is called multiple times before previous call completes
-- Solution: Implement a debounce/completion check system

local FavoritePromptDebounce = false
local FavoritePromptQueue = {}

function SafePromptSetFavorite(assetId, callback)
    -- Validate assetId
    if not assetId then
        warn("[PromptSetFavorite] No assetId provided!")
        if callback then callback(false, "No assetId provided") end
        return false
    end
    
    -- Check if already in progress
    if FavoritePromptDebounce then
        warn("[PromptSetFavorite] Already in progress, queuing request...")
        table.insert(FavoritePromptQueue, {assetId = assetId, callback = callback})
        return false
    end
    
    -- Set debounce
    FavoritePromptDebounce = true
    
    -- Execute the prompt with protection
    local success, result = pcall(function()
        return AvatarEditorService:PromptSetFavorite(assetId)
    end)
    
    if not success then
        warn("[PromptSetFavorite] Error:", result)
        FavoritePromptDebounce = false
        
        -- Process queue if any
        if #FavoritePromptQueue > 0 then
            local nextRequest = table.remove(FavoritePromptQueue, 1)
            task.delay(0.1, function()
                SafePromptSetFavorite(nextRequest.assetId, nextRequest.callback)
            end)
        end
        
        if callback then callback(false, result) end
        return false
    end
    
    -- Handle the result
    local isFavorite = (result == true)
    
    -- Reset debounce after a short delay to ensure completion
    task.delay(0.5, function()
        FavoritePromptDebounce = false
        
        -- Process queued requests one at a time
        if #FavoritePromptQueue > 0 then
            local nextRequest = table.remove(FavoritePromptQueue, 1)
            SafePromptSetFavorite(nextRequest.assetId, nextRequest.callback)
        end
    end)
    
    if callback then callback(isFavorite, nil) end
    return isFavorite
end

-- Alternative: Using Connection-based approach for better reliability
local favoritePromptConnection = nil
local favoritePending = false

function SafePromptSetFavoriteWithConnection(assetId, callback)
    if not assetId then
        warn("[PromptSetFavorite] No assetId provided!")
        if callback then callback(false, "No assetId provided") end
        return false
    end
    
    if favoritePending then
        warn("[PromptSetFavorite] Already pending, ignoring duplicate call")
        return false
    end
    
    favoritePending = true
    
    -- Disconnect any existing connection
    if favoritePromptConnection then
        favoritePromptConnection:Disconnect()
        favoritePromptConnection = nil
    end
    
    -- Connect to OnFavoriteChanged for completion detection
    favoritePromptConnection = AvatarEditorService.OnFavoriteChanged:Connect(function(id, isFav)
        if id == assetId then
            favoritePending = false
            if favoritePromptConnection then
                favoritePromptConnection:Disconnect()
                favoritePromptConnection = nil
            end
            if callback then callback(isFav, nil) end
        end
    end)
    
    -- Set a timeout as backup
    task.delay(5, function()
        if favoritePending then
            warn("[PromptSetFavorite] Timeout reached, resetting state")
            favoritePending = false
            if favoritePromptConnection then
                favoritePromptConnection:Disconnect()
                favoritePromptConnection = nil
            end
            if callback then callback(false, "Timeout") end
        end
    end)
    
    -- Actually call the prompt
    local success, result = pcall(function()
        return AvatarEditorService:PromptSetFavorite(assetId)
    end)
    
    if not success then
        favoritePending = false
        if favoritePromptConnection then
            favoritePromptConnection:Disconnect()
            favoritePromptConnection = nil
        end
        warn("[PromptSetFavorite] Error:", result)
        if callback then callback(false, result) end
    end
    
    return true
end

-- ============================================
-- FIX 3: Enhanced AvatarEditorService Wrapper
-- ============================================
-- Best practices wrapper for all AvatarEditorService operations

local AvatarEditorWrapper = {
    IsBusy = false,
    RequestQueue = {},
    CurrentRequestId = 0
}

function AvatarEditorWrapper:QueueRequest(requestType, params, callback)
    self.CurrentRequestId = self.CurrentRequestId + 1
    local requestId = self.CurrentRequestId
    
    local request = {
        id = requestId,
        type = requestType,
        params = params,
        callback = callback,
        timestamp = tick()
    }
    
    table.insert(self.RequestQueue, request)
    
    -- Process queue if not busy
    if not self.IsBusy then
        self:ProcessQueue()
    end
    
    return requestId
end

function AvatarEditorWrapper:ProcessQueue()
    if self.IsBusy or #self.RequestQueue == 0 then
        return
    end
    
    self.IsBusy = true
    local request = table.remove(self.RequestQueue, 1)
    
    -- Execute request with error handling
    local function executeRequest()
        local success, result = pcall(function()
            if request.type == "SetFavorite" then
                return AvatarEditorService:PromptSetFavorite(request.params.assetId)
            elseif request.type == "GetFavorite" then
                return AvatarEditorService:GetFavorite(request.params.assetId)
            else
                warn("[AvatarEditorWrapper] Unknown request type:", request.type)
                return nil
            end
        end)
        
        self.IsBusy = false
        
        if not success then
            warn("[AvatarEditorWrapper] Request failed:", result)
            if request.callback then request.callback(false, result) end
        else
            if request.callback then request.callback(result, nil) end
        end
        
        -- Process next request after delay
        task.delay(0.3, function()
            self:ProcessQueue()
        end)
    end
    
    -- Add timeout protection
    task.spawn(function()
        local startTime = tick()
        local timeout = 10 -- seconds
        
        executeRequest()
        
        -- Monitor for timeout
        while self.IsBusy and (tick() - startTime) < timeout do
            task.wait(0.1)
        end
        
        if self.IsBusy and (tick() - startTime) >= timeout then
            warn("[AvatarEditorWrapper] Request timed out, forcing reset")
            self.IsBusy = false
            if request.callback then request.callback(false, "Timeout") end
            self:ProcessQueue()
        end
    end)
end

function AvatarEditorWrapper:PromptSetFavorite(assetId, callback)
    return self:QueueRequest("SetFavorite", {assetId = assetId}, callback)
end

function AvatarEditorWrapper:GetFavorite(assetId, callback)
    return self:QueueRequest("GetFavorite", {assetId = assetId}, callback)
end

-- ============================================
-- USAGE EXAMPLES
-- ============================================

--[[
-- Example 1: Using SafeAddScale in your UI code
local myToggle = Library:AddToggle("ExampleToggle", {
    Text = "Enable Feature",
    Default = false
})

-- Safe way to add scale:
if myToggle and myToggle.TextLabel then
    SafeAddScale(myToggle, "ExampleScale", {
        Default = 1,
        Min = 0.1,
        Max = 5,
        Callback = function(value)
            print("Scale value changed:", value)
        end
    })
end

-- Example 2: Using SafePromptSetFavorite
local assetId = 12345678 -- Replace with actual asset ID

SafePromptSetFavorite(assetId, function(isFavorite, error)
    if error then
        warn("Failed to set favorite:", error)
    else
        print("Is now favorite:", isFavorite)
    end
end)

-- Example 3: Using the full wrapper (recommended for production)
AvatarEditorWrapper:PromptSetFavorite(assetId, function(result, error)
    if error then
        warn("Error:", error)
    else
        print("Favorite status:", result)
    end
end)

-- Example 4: Multiple requests (automatically queued)
for i = 1, 5 do
    AvatarEditorWrapper:PromptSetFavorite(i * 1000000, function(result, error)
        print("Request completed:", result, error)
    end)
end
-- These will be processed one at a time without errors
]]

-- ============================================
-- INTEGRATION WITH EXISTING LIBRARY
-- ============================================
-- If you want to integrate these fixes into Library.lua directly:

--[[
-- In Library.lua, modify the AddScale function (around line 412):

function Funcs:AddScale(Idx, Info)
    local ParentObj = self
    
    -- ADD THESE VALIDATION CHECKS:
    if not ParentObj then
        warn("[Library:AddScale] Parent object is nil")
        return nil
    end
    
    if not Info then
        warn("[Library:AddScale] Info table is nil")
        return nil
    end
    
    assert(Info.Default, 'AddScale: Missing default value.')
    assert(Info.Min, 'AddScale: Missing minimum value.')
    assert(Info.Max, 'AddScale: Missing maximum value.')
    
    -- Safe parent container resolution:
    local parentContainer = ParentObj.TextLabel or ParentObj.Outer
    
    if not parentContainer then
        warn("[Library:AddScale] No valid parent container found")
        return nil
    end
    
    -- Continue with rest of function...
    local Scale = {
        Value = Info.Default;
        Min = Info.Min or 0.1;
        Max = Info.Max or 5;
        Type = 'Scale';
        Callback = Info.Callback or function(Value) end;
    };
    
    -- ... rest of the function remains the same
end
]]

print("Avatar Editor Fixes loaded successfully!")
return {
    SafeAddScale = SafeAddScale,
    SafePromptSetFavorite = SafePromptSetFavorite,
    SafePromptSetFavoriteWithConnection = SafePromptSetFavoriteWithConnection,
    AvatarEditorWrapper = AvatarEditorWrapper
}
