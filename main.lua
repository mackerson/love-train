-- Utility function for smooth interpolation
function smoothstep(t)
    -- Smooth cubic interpolation (eases in and out)
    return t * t * (3 - 2 * t)
end

-- A* pathfinding to depot
function findPathToDepot(start_track)
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
    f_score[start_track] = heuristic(start_track, depot)
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
            if not isInSet(neighbor, closed_set) then
                local tentative_g = g_score[current] + distance(current, neighbor)
                
                if not isInSet(neighbor, open_set) then
                    table.insert(open_set, neighbor)
                elseif tentative_g >= g_score[neighbor] then
                    goto continue -- This path is not better
                end
                
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score[neighbor] = g_score[neighbor] + heuristic(neighbor, depot)
                
                ::continue::
            end
        end
    end
    
    return nil -- No path found
end

function heuristic(track, depot_pos)
    -- Manhattan distance to depot
    return math.abs(track.x - depot_pos.x) + math.abs(track.y - depot_pos.y)
end

function distance(track1, track2)
    return math.sqrt((track1.x - track2.x)^2 + (track1.y - track2.y)^2)
end

function isInSet(item, set)
    for _, v in ipairs(set) do
        if v == item then
            return true
        end
    end
    return false
end

function love.load()
    -- Enable console on Windows for debugging
    if love.system.getOS() == "Windows" then
        love.window.showMessageBox("Debug", "Console enabled - check for debug output", "info")
        -- Console should be enabled via conf.lua, but we'll also add visual feedback
    end
    
    -- Game settings
    love.window.setTitle("Train Prototype")
    love.window.setMode(0, 0, {fullscreen = true}) -- True fullscreen
    love.graphics.setBackgroundColor(0.2, 0.6, 0.2) -- Green background
    
    -- World and screen dimensions
    SCREEN_WIDTH = love.graphics.getWidth()
    SCREEN_HEIGHT = love.graphics.getHeight()
    WORLD_WIDTH = SCREEN_WIDTH * 3 -- 3x screen width
    WORLD_HEIGHT = SCREEN_HEIGHT * 3 -- 3x screen height
    
    -- Track grid size
    GRID_SIZE = 40
    
    -- Camera system
    camera = {
        x = 0,
        y = 0,
        target_x = 0,
        target_y = 0,
        smooth = 5, -- Camera smoothing factor
        zoom = 1.0, -- Current zoom level
        min_zoom = 0.3,
        max_zoom = 3.0
    }
    
    -- Depot position (bottom center of screen initially)
    depot = {
        x = SCREEN_WIDTH / 2,
        y = SCREEN_HEIGHT - 100,
        width = 80,
        height = 60
    }
    
    -- Center camera on depot at startup
    camera.x = depot.x - SCREEN_WIDTH / 2
    camera.y = depot.y - SCREEN_HEIGHT / 2
    camera.target_x = camera.x
    camera.target_y = camera.y
    
    -- Track system
    tracks = {}
    track_map = {} -- Hash map for fast track lookup by position
    
    -- Train system
    trains = {}
    train_spawn_timer = 0
    TRAIN_SPAWN_INTERVAL = 3 -- seconds
    last_depot_track_index = 0 -- For alternating depot branch selection
    
    -- Position management - track which positions are occupied
    occupied_positions = {} -- Format: [x_y] = train_id
    
    -- Debug logging with UI panel settings
    debug_log = {}
    max_log_lines = 20 -- Increased for scrollable panel
    log_panel = {
        width = 400,
        height = 200,
        margin = 10,
        line_height = 15,
        scroll_offset = 0,
        max_visible_lines = 12
    }
    
    -- Input handling
    mouse_down = false
    last_placed_position = {x = nil, y = nil} -- Track debouncing
end

-- Position management functions
function getPositionKey(x, y)
    return x .. "_" .. y
end

function isPositionOccupied(x, y)
    local key = getPositionKey(x, y)
    return occupied_positions[key] ~= nil
end

function isPositionOccupiedByOther(x, y, train_id)
    local key = getPositionKey(x, y)
    local occupying_train = occupied_positions[key]
    return occupying_train ~= nil and occupying_train ~= train_id
end

function occupyPosition(x, y, train_id)
    local key = getPositionKey(x, y)
    occupied_positions[key] = train_id
end

function freePosition(x, y)
    local key = getPositionKey(x, y)
    occupied_positions[key] = nil
end

function clearTrainFromAllPositions(train_id)
    -- Remove this train from all occupied positions
    local positions_to_clear = {}
    for position_key, occupying_train_id in pairs(occupied_positions) do
        if occupying_train_id == train_id then
            table.insert(positions_to_clear, position_key)
        end
    end
    
    for _, position_key in ipairs(positions_to_clear) do
        occupied_positions[position_key] = nil
        debugLog("Cleared position " .. position_key .. " previously occupied by train " .. train_id)
    end
end

function getTrackAt(x, y)
    local key = getPositionKey(x, y)
    return track_map[key]
end

function debugLog(message)
    print(message) -- Console output
    table.insert(debug_log, message)
    -- Keep only last max_log_lines
    if #debug_log > max_log_lines then
        table.remove(debug_log, 1)
    end
    -- Auto-scroll to bottom when new messages arrive
    log_panel.scroll_offset = math.max(0, #debug_log - log_panel.max_visible_lines)
end

function drawDebugLogPanel()
    local panel = log_panel
    local panel_x = SCREEN_WIDTH - panel.width - panel.margin
    local panel_y = SCREEN_HEIGHT - panel.height - panel.margin
    
    -- Draw panel background
    love.graphics.setColor(0, 0, 0, 0.8) -- Semi-transparent black
    love.graphics.rectangle("fill", panel_x, panel_y, panel.width, panel.height)
    
    -- Draw panel border
    love.graphics.setColor(0.3, 0.3, 0.3, 1) -- Gray border
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, panel.width, panel.height)
    love.graphics.setLineWidth(1) -- Reset line width
    
    -- Draw title
    love.graphics.setColor(1, 1, 0.5) -- Light yellow for title
    love.graphics.print("=== TRAIN LOG ===", panel_x + 10, panel_y + 5)
    
    -- Calculate which log lines to show based on scroll offset
    local start_line = math.max(1, panel.scroll_offset + 1)
    local end_line = math.min(#debug_log, start_line + panel.max_visible_lines - 1)
    
    -- Draw log lines
    love.graphics.setColor(1, 1, 1) -- White for log text
    local text_y = panel_y + 25 -- Start below title
    
    for i = start_line, end_line do
        local log_line = debug_log[i]
        -- Truncate long lines to fit in panel
        if love.graphics.getFont():getWidth(log_line) > panel.width - 20 then
            log_line = string.sub(log_line, 1, 50) .. "..."
        end
        love.graphics.print(log_line, panel_x + 10, text_y)
        text_y = text_y + panel.line_height
    end
    
    -- Draw scrollbar if needed
    if #debug_log > panel.max_visible_lines then
        drawLogScrollbar(panel_x, panel_y)
    end
    
    -- Draw scroll instructions
    if #debug_log > panel.max_visible_lines then
        love.graphics.setColor(0.7, 0.7, 0.7) -- Gray for instructions
        love.graphics.print("↑↓ to scroll", panel_x + panel.width - 70, panel_y + panel.height - 15)
    end
end

function drawLogScrollbar(panel_x, panel_y)
    local panel = log_panel
    local scrollbar_x = panel_x + panel.width - 15
    local scrollbar_y = panel_y + 25
    local scrollbar_height = panel.height - 45
    
    -- Draw scrollbar track
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", scrollbar_x, scrollbar_y, 10, scrollbar_height)
    
    -- Calculate thumb position and size
    local total_lines = #debug_log
    local visible_ratio = panel.max_visible_lines / total_lines
    local thumb_height = math.max(20, scrollbar_height * visible_ratio)
    local scroll_ratio = panel.scroll_offset / (total_lines - panel.max_visible_lines)
    local thumb_y = scrollbar_y + scroll_ratio * (scrollbar_height - thumb_height)
    
    -- Draw scrollbar thumb
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    love.graphics.rectangle("fill", scrollbar_x, thumb_y, 10, thumb_height)
end

function love.update(dt)
    -- Update camera to follow mouse for now (can be changed later)
    local mouse_x, mouse_y = love.mouse.getPosition()
    camera.target_x = (mouse_x - SCREEN_WIDTH/2) * 0.5 / camera.zoom -- Gentle mouse following adjusted for zoom
    camera.target_y = (mouse_y - SCREEN_HEIGHT/2) * 0.5 / camera.zoom
    
    -- Clamp camera to world bounds
    camera.target_x = math.max(-WORLD_WIDTH/2 + SCREEN_WIDTH/2, math.min(WORLD_WIDTH/2 - SCREEN_WIDTH/2, camera.target_x))
    camera.target_y = math.max(-WORLD_HEIGHT/2 + SCREEN_HEIGHT/2, math.min(WORLD_HEIGHT/2 - SCREEN_HEIGHT/2, camera.target_y))
    
    -- Smooth camera movement
    camera.x = camera.x + (camera.target_x - camera.x) * camera.smooth * dt
    camera.y = camera.y + (camera.target_y - camera.y) * camera.smooth * dt
    
    -- Manual train spawning only (removed automatic spawning)
    
    -- Update trains
    for i = #trains, 1, -1 do
        local train = trains[i]
        updateTrain(train, dt)
        
        -- Remove trains that have returned to depot
        if train.direction == -1 and 
           math.abs(train.x - depot.x) < 20 and 
           math.abs(train.y - depot.y) < 20 and
           train.current_track == nil then
            debugLog("REMOVING Train " .. train.id .. " - returned to depot")
            -- Free any positions this train might still be occupying
            clearTrainFromAllPositions(train.id)
            table.remove(trains, i)
        end
    end
end

function love.draw()
    -- Apply camera transform
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)
    love.graphics.scale(camera.zoom, camera.zoom)
    
    -- Draw world grid (optional visual aid)
    love.graphics.setColor(0.15, 0.5, 0.15, 0.3) -- Faint green grid
    for x = -WORLD_WIDTH/2, WORLD_WIDTH/2, GRID_SIZE do
        love.graphics.line(x, -WORLD_HEIGHT/2, x, WORLD_HEIGHT/2)
    end
    for y = -WORLD_HEIGHT/2, WORLD_HEIGHT/2, GRID_SIZE do
        love.graphics.line(-WORLD_WIDTH/2, y, WORLD_WIDTH/2, y)
    end
    
    -- Draw depot connection range (visual aid)
    love.graphics.setColor(0.8, 0.8, 0.1, 0.2) -- Yellow circle for connection range
    love.graphics.circle("line", depot.x, depot.y, GRID_SIZE * 3)
    
    -- Draw depot
    love.graphics.setColor(0.6, 0.3, 0.1) -- Brown
    love.graphics.rectangle("fill", depot.x - depot.width/2, depot.y - depot.height/2, depot.width, depot.height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("DEPOT", depot.x - 20, depot.y - 5)
    
    -- Draw tracks
    love.graphics.setColor(0.4, 0.4, 0.4) -- Gray
    for _, track in ipairs(tracks) do
        drawTrack(track)
    end
    
    -- Draw trains
    for _, train in ipairs(trains) do
        -- Train color and movement indicators
        local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 10)
        
        if train.direction == -1 then
            -- Returning trains are blue with gentle pulsing
            love.graphics.setColor(0.1 * pulse, 0.1 * pulse, 0.8 * pulse)
        else
            -- Outbound trains are red with gentle pulsing
            love.graphics.setColor(0.8 * pulse, 0.1 * pulse, 0.1 * pulse)
        end
        
        -- Draw train as a circle
        love.graphics.circle("fill", train.x, train.y, 8)
        
        -- Draw direction indicator
        love.graphics.setColor(1, 1, 1) -- White
        local target_x, target_y
        if train.direction == -1 then
            -- Returning to depot
            target_x = depot.x
            target_y = depot.y
        else
            -- Going outbound
            if train.target_track then
                target_x = train.target_track.x
                target_y = train.target_track.y
            else
                target_x = train.x
                target_y = train.y
            end
        end
        
        -- Draw arrow showing direction
        local dx = target_x - train.x
        local dy = target_y - train.y
        local dist = math.sqrt(dx^2 + dy^2)
        if dist > 0 then
            dx = dx / dist
            dy = dy / dist
            local arrow_size = 4
            love.graphics.line(train.x, train.y, 
                             train.x + dx * arrow_size, train.y + dy * arrow_size)
        end
    end
    
    -- Reset camera transform
    love.graphics.pop()
    
    -- Draw UI (not affected by camera)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("CLICK: Place/Remove tracks | SPACE: Spawn train | ESC: Quit | ↑↓: Scroll log", 10, 10)
    love.graphics.print("Move mouse to pan camera! | Mouse wheel: Zoom", 10, 30)
    love.graphics.print("Trains: " .. #trains .. " | Tracks: " .. #tracks .. " | Zoom: " .. string.format("%.1f", camera.zoom) .. "x", 10, 50)
    
    -- Count occupied positions for debugging
    local occupied_count = 0
    for _ in pairs(occupied_positions) do
        occupied_count = occupied_count + 1
    end
    love.graphics.print("Red=outbound, Blue=returning | Occupied positions: " .. occupied_count, 10, 70)
    
    -- Draw debug log panel in lower right
    drawDebugLogPanel()
end

function love.mousepressed(x, y, button)
    if button == 1 then -- Left click
        mouse_down = true
        -- Convert screen coordinates to world coordinates accounting for zoom
        local world_x = x / camera.zoom + camera.x
        local world_y = y / camera.zoom + camera.y
        placeTrack(world_x, world_y)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if mouse_down then
        -- Convert screen coordinates to world coordinates accounting for zoom
        local world_x = x / camera.zoom + camera.x
        local world_y = y / camera.zoom + camera.y
        placeTrack(world_x, world_y)
    end
end

function love.mousereleased(x, y, button)
    if button == 1 then
        mouse_down = false
        -- Reset debounce position when mouse is released
        last_placed_position.x = nil
        last_placed_position.y = nil
    end
end

function love.keypressed(key)
    if key == "space" then
        spawnTrain()
        debugLog("=== SPAWNED TRAIN ===")
    elseif key == "escape" then
        love.event.quit()
    elseif key == "up" then
        scrollLog(-1)
    elseif key == "down" then
        scrollLog(1)
    end
end

function love.wheelmoved(x, y)
    -- y > 0 = wheel up (zoom in), y < 0 = wheel down (zoom out)
    local zoom_factor = 1.1
    local old_zoom = camera.zoom
    
    if y > 0 then
        camera.zoom = math.min(camera.max_zoom, camera.zoom * zoom_factor)
    elseif y < 0 then
        camera.zoom = math.max(camera.min_zoom, camera.zoom / zoom_factor)
    end
    
    -- Get mouse position for zoom center
    local mouse_x, mouse_y = love.mouse.getPosition()
    local world_x = mouse_x + camera.x
    local world_y = mouse_y + camera.y
    
    -- Adjust camera position to zoom toward mouse cursor
    local zoom_ratio = camera.zoom / old_zoom
    camera.x = world_x - (world_x - camera.x) * zoom_ratio
    camera.y = world_y - (world_y - camera.y) * zoom_ratio
    camera.target_x = camera.x
    camera.target_y = camera.y
end

function scrollLog(direction)
    local panel = log_panel
    local max_scroll = math.max(0, #debug_log - panel.max_visible_lines)
    
    panel.scroll_offset = math.max(0, math.min(max_scroll, panel.scroll_offset + direction))
end

function placeTrack(x, y)
    -- Snap to grid
    local grid_x = math.floor(x / GRID_SIZE) * GRID_SIZE + GRID_SIZE/2
    local grid_y = math.floor(y / GRID_SIZE) * GRID_SIZE + GRID_SIZE/2
    
    -- Don't place tracks too close to depot
    if math.abs(grid_x - depot.x) < depot.width and math.abs(grid_y - depot.y) < depot.height then
        return
    end
    
    -- Debounce: don't place/remove at same position as last operation
    if last_placed_position.x == grid_x and last_placed_position.y == grid_y then
        return
    end
    
    -- Check if track already exists at this position - if so, remove it
    for i, track in ipairs(tracks) do
        if track.x == grid_x and track.y == grid_y then
            removeTrack(track, i)
            last_placed_position.x = grid_x
            last_placed_position.y = grid_y
            return
        end
    end
    
    -- Add new track with unique ID
    local track_id = "track_" .. grid_x .. "_" .. grid_y .. "_" .. love.timer.getTime()
    local new_track = {
        id = track_id,
        x = grid_x,
        y = grid_y,
        connections = {},
        track_type = "basic", -- For future expansion
        health = 100 -- For future track degradation
    }
    
    table.insert(tracks, new_track)
    
    -- Add to hash map for fast lookup
    local position_key = getPositionKey(grid_x, grid_y)
    track_map[position_key] = new_track
    
    -- Auto-connect to nearby tracks
    connectTracks(new_track)
    
    -- Update last placed position for debouncing
    last_placed_position.x = grid_x
    last_placed_position.y = grid_y
end

function removeTrack(track_to_remove, track_index)
    debugLog("Removing track " .. track_to_remove.id .. " at (" .. track_to_remove.x .. "," .. track_to_remove.y .. ")")
    
    -- Remove from track_map
    local position_key = getPositionKey(track_to_remove.x, track_to_remove.y)
    track_map[position_key] = nil
    
    -- Remove connections from other tracks to this track
    for _, other_track in ipairs(tracks) do
        if other_track ~= track_to_remove then
            for i = #other_track.connections, 1, -1 do
                if other_track.connections[i] == track_to_remove then
                    table.remove(other_track.connections, i)
                end
            end
        end
    end
    
    -- Free any occupied position
    freePosition(track_to_remove.x, track_to_remove.y)
    
    -- Remove from tracks array
    table.remove(tracks, track_index)
    
    -- Check if any trains are currently on this track and handle them
    for _, train in ipairs(trains) do
        if train.current_track == track_to_remove then
            debugLog("Train " .. train.id .. " was on removed track - forcing reversal")
            train.direction = -1 -- Force return to depot
            train.current_track = nil
        end
        if train.target_track == track_to_remove then
            train.target_track = nil
        end
        -- No additional cleanup needed with simplified pathfinding
    end
end

function connectTracks(new_track)
    for _, track in ipairs(tracks) do
        if track ~= new_track then
            local distance = math.sqrt((track.x - new_track.x)^2 + (track.y - new_track.y)^2)
            if distance <= GRID_SIZE * 1.1 then -- Allow slight tolerance
                -- Connect tracks bidirectionally
                table.insert(new_track.connections, track)
                table.insert(track.connections, new_track)
            end
        end
    end
    
    -- Connect to depot if close enough (increased range and made more forgiving)
    local depot_distance = math.sqrt((depot.x - new_track.x)^2 + (depot.y - new_track.y)^2)
    if depot_distance <= GRID_SIZE * 3 then -- Increased from 2 to 3 for easier connection
        new_track.connected_to_depot = true
    end
end

function drawTrack(track)
    -- Draw track piece (different color if connected to depot)
    if track.connected_to_depot then
        love.graphics.setColor(0.6, 0.6, 0.2) -- Yellow-ish for depot-connected tracks
    else
        love.graphics.setColor(0.4, 0.4, 0.4) -- Gray for regular tracks
    end
    love.graphics.rectangle("fill", track.x - 15, track.y - 5, 30, 10)
    
    -- Draw connections between tracks
    love.graphics.setColor(0.3, 0.3, 0.3)
    for _, connected_track in ipairs(track.connections) do
        love.graphics.line(track.x, track.y, connected_track.x, connected_track.y)
    end
    
    -- Draw connection to depot (more prominent)
    if track.connected_to_depot then
        love.graphics.setColor(0.8, 0.8, 0.1) -- Bright yellow for depot connection
        love.graphics.setLineWidth(3)
        love.graphics.line(track.x, track.y, depot.x, depot.y)
        love.graphics.setLineWidth(1) -- Reset line width
    end
end

function spawnTrain()
    -- Find tracks connected to depot
    local depot_tracks = {}
    for _, track in ipairs(tracks) do
        if track.connected_to_depot then
            table.insert(depot_tracks, track)
        end
    end
    
    if #depot_tracks == 0 then 
        debugLog("No depot tracks found - cannot spawn train")
        return 
    end
    
    -- Sort depot tracks clockwise by angle from depot center
    table.sort(depot_tracks, function(a, b)
        local angle_a = math.atan2(a.y - depot.y, a.x - depot.x)
        local angle_b = math.atan2(b.y - depot.y, b.x - depot.x)
        return angle_a < angle_b
    end)
    
    -- Spawn simple train at depot
    local train_id = math.floor(love.timer.getTime() * 100) -- Simpler ID for logging
    
    -- Alternate between depot tracks clockwise, but skip occupied ones
    local attempts = 0
    local target = nil
    
    while attempts < #depot_tracks do
        last_depot_track_index = (last_depot_track_index % #depot_tracks) + 1
        local candidate = depot_tracks[last_depot_track_index]
        
        -- Check if this depot track is clear
        if not isPositionOccupiedByOther(candidate.x, candidate.y, -1) then -- Use -1 as dummy train ID
            target = candidate
            break
        end
        
        attempts = attempts + 1
    end
    
    if not target then
        debugLog("All depot tracks are occupied - cannot spawn train")
        return
    end
    local train = {
        id = train_id,
        x = depot.x,
        y = depot.y,
        target_track = target,
        current_track = nil, -- Track we're currently on
        came_from = nil, -- Track we came from (for dead end detection)
        direction = 1, -- 1 = outbound from depot, -1 = returning to depot
        spawn_delay = 0.5 -- Small delay before train starts moving
    }
    
    debugLog("Train " .. train.id .. " spawned at depot, targeting clear branch " .. last_depot_track_index .. " at (" .. target.x .. "," .. target.y .. ")")
    table.insert(trains, train)
end

function updateTrain(train, dt)
    local TRAIN_SPEED = 60 -- pixels per second
    
    -- Handle spawn delay
    if train.spawn_delay and train.spawn_delay > 0 then
        train.spawn_delay = train.spawn_delay - dt
        if train.spawn_delay > 0 then
            return -- Don't move yet
        else
            train.spawn_delay = nil -- Remove delay once it's done
            debugLog("Train " .. train.id .. " spawn delay complete, starting movement")
        end
    end
    
    -- Determine target position based on current state
    local target_x, target_y
    if train.target_track then
        target_x = train.target_track.x
        target_y = train.target_track.y
    elseif train.direction == -1 then
        -- Returning to depot
        target_x = depot.x
        target_y = depot.y
    else
        -- No target, stay in place
        target_x = train.x
        target_y = train.y
    end
    
    -- Calculate direction and distance to target
    local dx = target_x - train.x
    local dy = target_y - train.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- If we're close enough to target, handle arrival logic
    if distance < 5 then
        -- Snap to exact target position
        train.x = target_x
        train.y = target_y
        
        -- Handle arrival at target
        handleTrainArrival(train)
    else
        -- Move toward target at constant speed
        local move_distance = TRAIN_SPEED * dt
        if move_distance > distance then
            move_distance = distance -- Don't overshoot
        end
        
        -- Normalize direction and apply movement
        local dir_x = dx / distance
        local dir_y = dy / distance
        train.x = train.x + dir_x * move_distance
        train.y = train.y + dir_y * move_distance
    end
end

function handleTrainArrival(train)
    local current_track_info = train.current_track and ("Track " .. train.current_track.id) or "Depot"
    debugLog("Train " .. train.id .. " arrived. Direction: " .. train.direction .. " Current: (" .. train.x .. "," .. train.y .. ") on " .. current_track_info)
    
    -- Free current position (unless at depot)
    if train.current_track then
        freePosition(train.x, train.y)
    end
    
    -- Store where we came from before moving
    local previous_track = train.current_track
    
    -- Update current track based on where we arrived
    if train.target_track and math.abs(train.x - train.target_track.x) < 5 and math.abs(train.y - train.target_track.y) < 5 then
        -- Arrived at a track
        train.current_track = train.target_track
        train.came_from = previous_track
        occupyPosition(train.x, train.y, train.id)
        debugLog("Train " .. train.id .. " arrived at track " .. train.current_track.id)
    elseif math.abs(train.x - depot.x) < 5 and math.abs(train.y - depot.y) < 5 then
        -- Arrived at depot
        train.current_track = nil
        train.came_from = previous_track
        debugLog("Train " .. train.id .. " arrived at depot")
        return -- Stay at depot
    end
    
    -- Determine next target based on direction
    local next_target = nil
    
    if train.direction == 1 then
        -- Going outbound: explore further
        if train.current_track then
            next_target = findNextTrack(train)
            if not next_target then
                -- Dead end - reverse direction and go back the way we came
                train.direction = -1
                debugLog("Train " .. train.id .. " hit dead end, reversing")
                -- Simply go back to where we came from
                next_target = train.came_from
            end
        end
    else
        -- Returning: use A* to find best route back
        if train.current_track then
            -- Always use A* pathfinding to ensure trains follow tracks
            local path = findPathToDepot(train.current_track)
            if path and #path > 0 then
                -- If path only contains current track, it means we can go direct to depot
                if #path == 1 and path[1] == train.current_track and train.current_track.connected_to_depot then
                    next_target = nil -- Go directly to depot
                    debugLog("Train " .. train.id .. " taking direct route to depot from connected track")
                else
                    -- Take the first step in the optimal path
                    for _, track in ipairs(path) do
                        if track ~= train.current_track and not isPositionOccupiedByOther(track.x, track.y, train.id) then
                            next_target = track
                            break
                        end
                    end
                    if not next_target then
                        -- All tracks in path are occupied, try going to depot if connected
                        if train.current_track.connected_to_depot then
                            next_target = nil -- Go to depot
                            debugLog("Train " .. train.id .. " path blocked, taking direct route to depot")
                        end
                    end
                end
            else
                debugLog("Train " .. train.id .. " ERROR: No path to depot found!")
            end
        end
    end
    
    -- Check for collisions with next target
    if next_target and isPositionOccupiedByOther(next_target.x, next_target.y, train.id) then
        local occupying_train_id = occupied_positions[getPositionKey(next_target.x, next_target.y)]
        debugLog("Train " .. train.id .. " collision ahead with train " .. occupying_train_id .. " on " .. next_target.id)
        
        -- If we're going outbound and hit a collision, reverse direction
        if train.direction == 1 then
            train.direction = -1
            debugLog("Train " .. train.id .. " reversing due to collision")
            -- Try to go back where we came from
            next_target = train.came_from
        else
            -- If we're already returning and hit collision, just wait
            next_target = nil
        end
    end
    
    train.target_track = next_target
    local target_info = next_target and ("Track " .. next_target.id) or "Depot"
    debugLog("Train " .. train.id .. " new target: " .. target_info)
end

function hasForwardConnection(track, came_from_track)
    -- Check if track has any connections other than the one we came from
    for _, connected_track in ipairs(track.connections) do
        if connected_track ~= came_from_track then
            return true
        end
    end
    return false
end


function findNextTrack(train)
    if not train.current_track then return nil end
    
    -- Find any connected track that we didn't just come from
    for _, connected_track in ipairs(train.current_track.connections) do
        -- Don't go back where we came from
        if connected_track ~= train.came_from then
            return connected_track
        end
    end
    
    -- No forward options found - we've hit a dead end
    return nil
end
