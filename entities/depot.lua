local Class = require('lib.base-class')
local Train = require('entities.train')

local Depot = Class:extend()

function Depot:set(x, y, width, height, grid_size)
    self.x = x
    self.y = y
    self.width = width or 80
    self.height = height or 60
    self.grid_size = grid_size or 40
    self.last_depot_track_index = 0 -- For alternating depot branch selection
end

function Depot:draw()
    -- Draw depot building
    love.graphics.setColor(0.6, 0.3, 0.1) -- Brown
    love.graphics.rectangle("fill", self.x - self.width/2, self.y - self.height/2, self.width, self.height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("DEPOT", self.x - 20, self.y - 5)
end

function Depot:drawConnectionRange()
    -- Draw depot connection range (visual aid)
    love.graphics.setColor(0.8, 0.8, 0.1, 0.2) -- Yellow circle for connection range
    love.graphics.circle("line", self.x, self.y, self.grid_size * 3)
end

function Depot:spawnTrain(tracks, occupied_positions, debug_log)
    -- Find tracks connected to depot
    local depot_tracks = self:getConnectedTracks(tracks)
    
    if #depot_tracks == 0 then 
        debug_log:log("No depot tracks found - cannot spawn train")
        return nil
    end
    
    -- Sort depot tracks clockwise by angle from depot center
    table.sort(depot_tracks, function(a, b)
        local angle_a = math.atan2(a.y - self.y, a.x - self.x)
        local angle_b = math.atan2(b.y - self.y, b.x - self.x)
        return angle_a < angle_b
    end)
    
    -- Generate train ID
    local train_id = math.floor(love.timer.getTime() * 100) -- Simpler ID for logging
    
    -- Alternate between depot tracks clockwise, but skip occupied ones
    local attempts = 0
    local target = nil
    
    while attempts < #depot_tracks do
        self.last_depot_track_index = (self.last_depot_track_index % #depot_tracks) + 1
        local candidate = depot_tracks[self.last_depot_track_index]
        
        -- Check if this depot track is clear
        if not self:isPositionOccupiedByOther(candidate.x, candidate.y, train_id, occupied_positions) then
            target = candidate
            break
        end
        
        attempts = attempts + 1
    end
    
    if not target then
        debug_log:log("All depot tracks are occupied - cannot spawn train")
        return nil
    end
    
    -- Create new train
    local train = Train:new(train_id, self.x, self.y, target)
    
    debug_log:log("Train " .. train.id .. " spawned at depot, targeting clear branch " .. self.last_depot_track_index .. " at (" .. target.x .. "," .. target.y .. ")")
    
    return train
end

function Depot:getConnectedTracks(tracks)
    local depot_tracks = {}
    for _, track in ipairs(tracks) do
        if track.connected_to_depot then
            table.insert(depot_tracks, track)
        end
    end
    return depot_tracks
end

function Depot:isPositionOccupiedByOther(x, y, train_id, occupied_positions)
    local key = x .. "_" .. y
    local occupying_train = occupied_positions[key]
    return occupying_train ~= nil and occupying_train ~= train_id
end

function Depot:isTrainAtDepot(train)
    return train.logical_x == self.x and train.logical_y == self.y
end

function Depot:canTrainEnter(train, occupied_positions)
    -- Depot can always accept returning trains
    return true
end

return Depot
