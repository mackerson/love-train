local Class = require('lib.base-class')

local Track = Class:extend()

function Track:set(id, x, y, grid_size)
    self.id = id
    self.x = x
    self.y = y
    self.connections = {}
    self.track_type = "basic" -- For future expansion
    self.health = 100 -- For future track degradation
    self.connected_to_depot = false
    self.grid_size = grid_size or 40
end

function Track:draw()
    -- Draw track piece (different color if connected to depot)
    if self.connected_to_depot then
        love.graphics.setColor(0.6, 0.6, 0.2) -- Yellow-ish for depot-connected tracks
    else
        love.graphics.setColor(0.4, 0.4, 0.4) -- Gray for regular tracks
    end
    love.graphics.rectangle("fill", self.x - 15, self.y - 5, 30, 10)
    
    -- Draw connections between tracks
    love.graphics.setColor(0.3, 0.3, 0.3)
    for _, connected_track in ipairs(self.connections) do
        love.graphics.line(self.x, self.y, connected_track.x, connected_track.y)
    end
end

function Track:drawDepotConnection(depot)
    -- Draw connection to depot (more prominent)
    if self.connected_to_depot then
        love.graphics.setColor(0.8, 0.8, 0.1) -- Bright yellow for depot connection
        love.graphics.setLineWidth(3)
        love.graphics.line(self.x, self.y, depot.x, depot.y)
        love.graphics.setLineWidth(1) -- Reset line width
    end
end

function Track:connectTo(other_track)
    -- Connect tracks bidirectionally
    if not self:isConnectedTo(other_track) then
        table.insert(self.connections, other_track)
        table.insert(other_track.connections, self)
    end
end

function Track:disconnectFrom(other_track)
    -- Remove bidirectional connection
    for i = #self.connections, 1, -1 do
        if self.connections[i] == other_track then
            table.remove(self.connections, i)
        end
    end
    
    for i = #other_track.connections, 1, -1 do
        if other_track.connections[i] == self then
            table.remove(other_track.connections, i)
        end
    end
end

function Track:isConnectedTo(other_track)
    for _, connected_track in ipairs(self.connections) do
        if connected_track == other_track then
            return true
        end
    end
    return false
end

function Track:checkDepotConnection(depot)
    -- Connect to depot if close enough
    local depot_distance = math.sqrt((depot.x - self.x)^2 + (depot.y - self.y)^2)
    if depot_distance <= self.grid_size * 3 then -- 3 grid units for easier connection
        self.connected_to_depot = true
        return true
    else
        self.connected_to_depot = false
        return false
    end
end

function Track:getDistanceTo(other_track)
    return math.sqrt((self.x - other_track.x)^2 + (self.y - other_track.y)^2)
end

return Track
