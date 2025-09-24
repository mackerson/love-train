local Class = require('lib.base-class')
local Track = require('entities.track')
local WorldConfig = require('config.world-config')

local TrackManager = Class:extend()

function TrackManager:set(grid_size)
    self.tracks = {}
    self.track_map = {} -- Hash map for fast track lookup by position
    self.grid_size = grid_size or 40
end

function TrackManager:update(dt)
    -- Tracks don't need updating currently, but method exists for future features
end

function TrackManager:draw(depot)
    -- Draw all tracks
    love.graphics.setColor(0.4, 0.4, 0.4) -- Gray
    for _, track in ipairs(self.tracks) do
        track:draw()
    end
    
    -- Draw depot connections
    for _, track in ipairs(self.tracks) do
        track:drawDepotConnection(depot)
    end
end

function TrackManager:placeTrack(world_x, world_y, depot, last_placed_position)
    -- Convert to tile coordinates
    local tile_x, tile_y = WorldConfig.worldToTile(world_x, world_y)

    -- Validate within world bounds
    if not WorldConfig.isInTileBounds(tile_x, tile_y) then
        return false, last_placed_position
    end

    -- Convert back to world coordinates (centered in tile)
    local grid_x, grid_y = WorldConfig.tileCenterToWorld(tile_x, tile_y)
    
    -- Don't place tracks too close to depot
    if math.abs(grid_x - depot.x) < depot.width and math.abs(grid_y - depot.y) < depot.height then
        return false, last_placed_position
    end
    
    -- Debounce: don't place/remove at same position as last operation
    if last_placed_position.x == grid_x and last_placed_position.y == grid_y then
        return false, last_placed_position
    end
    
    -- Check if track already exists at this position - if so, remove it
    local existing_track = self:getTrackAt(grid_x, grid_y)
    if existing_track then
        self:removeTrack(existing_track, depot)
        last_placed_position.x = grid_x
        last_placed_position.y = grid_y
        return true, last_placed_position
    end
    
    -- Add new track with unique ID
    local track_id = "track_" .. grid_x .. "_" .. grid_y .. "_" .. love.timer.getTime()
    local new_track = Track:new(track_id, grid_x, grid_y, self.grid_size)
    
    table.insert(self.tracks, new_track)
    
    -- Add to hash map for fast lookup
    local position_key = self:getPositionKey(grid_x, grid_y)
    self.track_map[position_key] = new_track
    
    -- Auto-connect to nearby tracks
    self:connectTracks(new_track)
    
    -- Check depot connection
    new_track:checkDepotConnection(depot)
    
    -- Update last placed position for debouncing
    last_placed_position.x = grid_x
    last_placed_position.y = grid_y
    
    return true, last_placed_position
end

function TrackManager:removeTrack(track_to_remove, depot)
    -- Find track index
    local track_index = nil
    for i, track in ipairs(self.tracks) do
        if track == track_to_remove then
            track_index = i
            break
        end
    end
    
    if not track_index then return false end
    
    -- Remove from track_map
    local position_key = self:getPositionKey(track_to_remove.x, track_to_remove.y)
    self.track_map[position_key] = nil
    
    -- Remove connections from other tracks to this track
    for _, other_track in ipairs(self.tracks) do
        if other_track ~= track_to_remove then
            track_to_remove:disconnectFrom(other_track)
        end
    end
    
    -- Remove from tracks array
    table.remove(self.tracks, track_index)
    
    return true
end

function TrackManager:connectTracks(new_track)
    for _, track in ipairs(self.tracks) do
        if track ~= new_track then
            local distance = new_track:getDistanceTo(track)
            if distance <= self.grid_size * 1.1 then -- Allow slight tolerance
                new_track:connectTo(track)
            end
        end
    end
end

function TrackManager:getTrackAt(x, y)
    local key = self:getPositionKey(x, y)
    return self.track_map[key]
end

function TrackManager:getPositionKey(x, y)
    return x .. "_" .. y
end

function TrackManager:getAllTracks()
    return self.tracks
end

function TrackManager:getTrackCount()
    return #self.tracks
end

return TrackManager
