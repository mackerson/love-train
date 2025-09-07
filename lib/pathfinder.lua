local Class = require('lib.base-class')

local Pathfinder = Class:extend()

function Pathfinder:set()
    -- No initialization needed for stateless pathfinding
end

function Pathfinder:findPathToDepot(start_track, depot, tracks)
    if not start_track then return nil end
    
    -- If already connected to depot, direct path
    if start_track.connected_to_depot then
        return {start_track}
    end
    
    local open_set = {}
    local closed_set = {}
    local came_from = {}
    local g_score = {}
    local f_score = {}
    
    -- Initialize scores
    for _, track in ipairs(tracks) do
        g_score[track] = math.huge
        f_score[track] = math.huge
    end
    
    g_score[start_track] = 0
    f_score[start_track] = self:heuristic(start_track, depot)
    table.insert(open_set, start_track)
    
    while #open_set > 0 do
        -- Find node with lowest f_score
        local current = open_set[1]
        local current_index = 1
        for i, track in ipairs(open_set) do
            if f_score[track] < f_score[current] then
                current = track
                current_index = i
            end
        end
        
        -- Remove current from open_set
        table.remove(open_set, current_index)
        table.insert(closed_set, current)
        
        -- Check if we found a depot connection
        if current.connected_to_depot then
            -- Reconstruct path
            local path = {}
            local node = current
            while node do
                table.insert(path, 1, node) -- Insert at beginning
                node = came_from[node]
            end
            return path
        end
        
        -- Check all neighbors
        for _, neighbor in ipairs(current.connections) do
            if not self:isInSet(neighbor, closed_set) then
                local tentative_g = g_score[current] + self:distance(current, neighbor)
                
                if not self:isInSet(neighbor, open_set) then
                    table.insert(open_set, neighbor)
                elseif tentative_g >= g_score[neighbor] then
                    goto continue -- This path is not better
                end
                
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score[neighbor] = g_score[neighbor] + self:heuristic(neighbor, depot)
                
                ::continue::
            end
        end
    end
    
    return nil -- No path found
end

function Pathfinder:heuristic(track, depot)
    -- Manhattan distance to depot
    return math.abs(track.x - depot.x) + math.abs(track.y - depot.y)
end

function Pathfinder:distance(track1, track2)
    return math.sqrt((track1.x - track2.x)^2 + (track1.y - track2.y)^2)
end

function Pathfinder:isInSet(item, set)
    for _, v in ipairs(set) do
        if v == item then
            return true
        end
    end
    return false
end

return Pathfinder
