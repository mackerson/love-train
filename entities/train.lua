local Class = require('lib.base-class')

local Train = Class:extend()

-- Train behavior constants
local TRAIN_STOP_WAIT_TIME = 2.0 -- seconds to wait when stopped by collision
local MOVE_INTERVAL = 1.0 -- Logical movement every 1 second

function Train:set(id, depot_x, depot_y, target_track)
    self.id = id
    self.x = depot_x -- Visual position
    self.y = depot_y -- Visual position
    self.logical_x = depot_x -- Logical grid position
    self.logical_y = depot_y -- Logical grid position
    self.target_track = target_track
    self.current_track = nil -- Track we're currently on
    self.came_from = nil -- Track we came from (for dead end detection)
    self.direction = 1 -- 1 = outbound from depot, -1 = returning to depot
    self.spawn_delay = 0.5 -- Small delay before train starts moving
    self.state = "moving" -- "moving", "stopped", "off_track"
    self.stop_timer = 0 -- Timer for how long train has been stopped
    self.off_track_timer = 0 -- Timer for detecting off-track situations
    self.blocked_target = nil -- Remember what target was blocked when stopped
    self.move_timer = 0 -- Timer for smooth interpolation
    self.move_progress = 0 -- 0 to 1, progress between logical positions
end

function Train:update(dt, depot, tracks, occupied_positions, pathfinder, debug_log)
    -- Handle spawn delay
    if self.spawn_delay and self.spawn_delay > 0 then
        self.spawn_delay = self.spawn_delay - dt
        if self.spawn_delay > 0 then
            return -- Don't move yet
        else
            self.spawn_delay = nil -- Remove delay once it's done
            debug_log:log("Train " .. self.id .. " spawn delay complete, starting movement")
        end
    end
    
    -- Update movement timer and visual interpolation
    self.move_timer = self.move_timer + dt
    self.move_progress = math.min(1.0, self.move_timer / MOVE_INTERVAL)
    
    -- Check if train is off track and handle it
    if self.state ~= "off_track" and not self:isOnValidPosition(depot, tracks) then
        self.off_track_timer = self.off_track_timer + dt
        if self.off_track_timer > 0.5 then -- Give 0.5 seconds grace period
            self.state = "off_track"
            debug_log:log("Train " .. self.id .. " detected off track at (" .. self.x .. "," .. self.y .. ")")
        end
    else
        self.off_track_timer = 0 -- Reset timer if back on track
    end
    
    -- Handle different train states
    if self.state == "stopped" then
        self:handleStoppedState(dt, occupied_positions, debug_log)
        return -- Don't move while stopped
        
    elseif self.state == "off_track" then
        self:handleOffTrackState(tracks, occupied_positions, debug_log)
    end
    
    -- Only move if in moving state
    if self.state ~= "moving" then
        return
    end
    
    -- Determine target logical position
    local target_logical_x, target_logical_y = self:getTargetLogicalPosition(depot)
    
    -- Smooth visual interpolation between logical positions
    local t = self:smoothstep(self.move_progress)
    self.x = self.logical_x + (target_logical_x - self.logical_x) * t
    self.y = self.logical_y + (target_logical_y - self.logical_y) * t
    
    -- Handle logical movement at intervals
    if self.move_timer >= MOVE_INTERVAL then
        self.move_timer = 0
        self.move_progress = 0
        
        -- Check if we've reached the target logically
        if target_logical_x ~= self.logical_x or target_logical_y ~= self.logical_y then
            -- Move to target logical position
            self.logical_x = target_logical_x
            self.logical_y = target_logical_y
            
            -- Handle arrival at logical target
            self:handleArrival(depot, tracks, occupied_positions, pathfinder, debug_log)
        end
    end
end

function Train:draw(depot)
    -- Train color and movement indicators
    local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 10)
    
    if self.state == "stopped" then
        -- Stopped trains are yellow with pulsing
        love.graphics.setColor(0.9 * pulse, 0.9 * pulse, 0.1 * pulse)
    elseif self.state == "off_track" then
        -- Off-track trains are magenta with fast pulsing
        local fast_pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 20)
        love.graphics.setColor(0.9 * fast_pulse, 0.1, 0.9 * fast_pulse)
    elseif self.direction == -1 then
        -- Returning trains are blue with gentle pulsing
        love.graphics.setColor(0.1 * pulse, 0.1 * pulse, 0.8 * pulse)
    else
        -- Outbound trains are red with gentle pulsing
        love.graphics.setColor(0.8 * pulse, 0.1 * pulse, 0.1 * pulse)
    end
    
    -- Draw train as a circle
    love.graphics.circle("fill", self.x, self.y, 8)
    
    -- Draw direction indicator
    self:drawDirectionArrow(depot)
end

function Train:drawDirectionArrow(depot)
    love.graphics.setColor(1, 1, 1) -- White
    local target_x, target_y = self:getArrowTarget(depot)
    
    -- Draw arrow showing direction
    local dx = target_x - self.x
    local dy = target_y - self.y
    local dist = math.sqrt(dx^2 + dy^2)
    if dist > 0 then
        dx = dx / dist
        dy = dy / dist
        local arrow_size = 4
        love.graphics.line(self.x, self.y, 
                         self.x + dx * arrow_size, self.y + dy * arrow_size)
    end
end

function Train:getArrowTarget(depot)
    if self.direction == -1 then
        -- Returning to depot
        return depot.x, depot.y
    else
        -- Going outbound
        if self.target_track then
            return self.target_track.x, self.target_track.y
        else
            return self.x, self.y
        end
    end
end

function Train:smoothstep(t)
    -- Smooth cubic interpolation (eases in and out)
    return t * t * (3 - 2 * t)
end

function Train:isOnValidPosition(depot, tracks)
    -- Check if at depot
    if self.logical_x == depot.x and self.logical_y == depot.y then
        return true
    end
    
    -- Check if on any track
    for _, track in ipairs(tracks) do
        if self.logical_x == track.x and self.logical_y == track.y then
            return true
        end
    end
    
    return false
end

function Train:getTargetLogicalPosition(depot)
    if self.target_track then
        return self.target_track.x, self.target_track.y
    elseif self.direction == -1 then
        -- Returning to depot
        return depot.x, depot.y
    else
        -- No target, stay at current logical position
        return self.logical_x, self.logical_y
    end
end

function Train:handleStoppedState(dt, occupied_positions, debug_log)
    -- Train is stopped due to collision, wait before trying again
    self.stop_timer = self.stop_timer + dt
    if self.stop_timer >= TRAIN_STOP_WAIT_TIME then
        self.state = "moving"
        self.stop_timer = 0
        debug_log:log("Train " .. self.id .. " resuming movement after stop")
        
        -- Check if the blocked path is now clear
        if self.blocked_target and not self:isPositionOccupiedByOther(self.blocked_target.x, self.blocked_target.y, occupied_positions) then
            -- Path is clear, continue with original plan
            debug_log:log("Train " .. self.id .. " blocked path now clear, continuing")
            self.target_track = self.blocked_target
            self.blocked_target = nil
        else
            -- Path still blocked or no blocked target, reverse direction
            if self.direction == 1 then
                self.direction = -1
                debug_log:log("Train " .. self.id .. " path still blocked, reversing direction")
            end
            self.blocked_target = nil
        end
    end
end

function Train:handleOffTrackState(tracks, occupied_positions, debug_log)
    -- Train is off track, return to nearest unoccupied track
    local nearest_track = self:findNearestUnoccupiedTrack(tracks, occupied_positions)
    if nearest_track then
        self.target_track = nearest_track
        self.state = "moving"
        debug_log:log("Train " .. self.id .. " returning to nearest track at (" .. nearest_track.x .. "," .. nearest_track.y .. ")")
    else
        -- No available tracks, return to depot
        self.target_track = nil
        self.direction = -1
        self.state = "moving"
        debug_log:log("Train " .. self.id .. " no available tracks, returning to depot")
    end
end

function Train:findNearestUnoccupiedTrack(tracks, occupied_positions)
    local nearest_track = nil
    local nearest_distance = math.huge
    
    for _, track in ipairs(tracks) do
        if not self:isPositionOccupiedByOther(track.x, track.y, occupied_positions) then
            local distance = math.sqrt((self.logical_x - track.x)^2 + (self.logical_y - track.y)^2)
            if distance < nearest_distance then
                nearest_distance = distance
                nearest_track = track
            end
        end
    end
    
    return nearest_track
end

function Train:isPositionOccupiedByOther(x, y, occupied_positions)
    local key = x .. "_" .. y
    local occupying_train = occupied_positions[key]
    return occupying_train ~= nil and occupying_train ~= self.id
end

function Train:handleArrival(depot, tracks, occupied_positions, pathfinder, debug_log)
    local current_track_info = self.current_track and ("Track " .. self.current_track.id) or "Depot"
    debug_log:log("Train " .. self.id .. " arrived. Direction: " .. self.direction .. " Logical: (" .. self.logical_x .. "," .. self.logical_y .. ") on " .. current_track_info)
    
    -- Free current position (unless at depot)
    if self.current_track then
        self:freePosition(self.current_track.x, self.current_track.y, occupied_positions)
        debug_log:log("Train " .. self.id .. " freed position (" .. self.current_track.x .. "," .. self.current_track.y .. ")")
    end
    
    -- Store where we came from before moving
    local previous_track = self.current_track
    
    -- Update current track based on logical arrival position
    if self.target_track and self.logical_x == self.target_track.x and self.logical_y == self.target_track.y then
        -- Arrived at a track
        self.current_track = self.target_track
        self.came_from = previous_track
        self:occupyPosition(self.logical_x, self.logical_y, occupied_positions)
        debug_log:log("Train " .. self.id .. " arrived at track " .. self.current_track.id)
    elseif self.logical_x == depot.x and self.logical_y == depot.y then
        -- Arrived at depot
        self.current_track = nil
        self.came_from = previous_track
        debug_log:log("Train " .. self.id .. " arrived at depot")
        return -- Stay at depot
    end
    
    -- Determine next target based on direction
    local next_target = self:findNextTarget(depot, pathfinder, debug_log, occupied_positions)
    
    -- Check for collisions with next target
    if next_target and self:isPositionOccupiedByOther(next_target.x, next_target.y, occupied_positions) then
        local occupying_train_id = occupied_positions[next_target.x .. "_" .. next_target.y]
        debug_log:log("Train " .. self.id .. " collision ahead with train " .. occupying_train_id .. " on " .. next_target.id .. " - stopping to wait")
        
        -- Stop and wait instead of immediately reversing
        self.state = "stopped"
        self.stop_timer = 0
        self.target_track = nil -- Don't move until we resume
        
        -- Store what we wanted to do for when we resume
        if self.direction == 1 then
            -- Remember that we wanted to explore this direction
            self.blocked_target = next_target
        end
        
        return -- Exit early, don't set new target
    end
    
    self.target_track = next_target
    local target_info = next_target and ("Track " .. next_target.id) or "Depot"
    debug_log:log("Train " .. self.id .. " new target: " .. target_info)
end

function Train:findNextTarget(depot, pathfinder, debug_log, occupied_positions)
    local next_target = nil
    
    if self.direction == 1 then
        -- Going outbound: explore further
        if self.current_track then
            next_target = self:findNextTrack()
            if not next_target then
                -- Dead end - reverse direction and go back the way we came
                self.direction = -1
                debug_log:log("Train " .. self.id .. " hit dead end, reversing")
                -- Simply go back to where we came from
                next_target = self.came_from
            end
        end
    else
        -- Returning: use pathfinder to find best route back
        if self.current_track then
            debug_log:log("DEBUG: Train " .. self.id .. " calling pathfinder with tracks count: " .. (tracks and #tracks or "nil"))
            local path = pathfinder.findPathToDepot(self.current_track, depot, tracks)
            if path and #path > 0 then
                -- If path only contains current track, it means we can go direct to depot
                if #path == 1 and path[1] == self.current_track and self.current_track.connected_to_depot then
                    next_target = nil -- Go directly to depot
                    debug_log:log("Train " .. self.id .. " taking direct route to depot from connected track")
                else
                    -- Take the first step in the optimal path
                    for _, track in ipairs(path) do
                        if track ~= self.current_track and not self:isPositionOccupiedByOther(track.x, track.y, occupied_positions) then
                            next_target = track
                            break
                        end
                    end
                    if not next_target then
                        -- All tracks in path are occupied, try going to depot if connected
                        if self.current_track.connected_to_depot then
                            next_target = nil -- Go to depot
                            debug_log:log("Train " .. self.id .. " path blocked, taking direct route to depot")
                        end
                    end
                end
            else
                debug_log:log("Train " .. self.id .. " ERROR: No path to depot found!")
            end
        end
    end
    
    return next_target
end

function Train:findNextTrack()
    if not self.current_track then return nil end
    
    -- Find any connected track that we didn't just come from
    for _, connected_track in ipairs(self.current_track.connections) do
        -- Don't go back where we came from
        if connected_track ~= self.came_from then
            return connected_track
        end
    end
    
    -- No forward options found - we've hit a dead end
    return nil
end

function Train:occupyPosition(x, y, occupied_positions)
    local key = x .. "_" .. y
    occupied_positions[key] = self.id
end

function Train:freePosition(x, y, occupied_positions)
    local key = x .. "_" .. y
    occupied_positions[key] = nil
end

return Train
