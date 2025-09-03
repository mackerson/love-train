function love.load()
    -- Enable console on Windows for debugging
    if love.system.getOS() == "Windows" then
        love.window.showMessageBox("Debug", "Console enabled - check for debug output", "info")
        -- Console should be enabled via conf.lua, but we'll also add visual feedback
    end
    
    -- Game settings
    love.window.setTitle("Train Prototype")
    love.window.setMode(0, 0, {fullscreen = false, borderless = true}) -- Windowed fullscreen
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
        smooth = 5 -- Camera smoothing factor
    }
    
    -- Depot position (bottom center of screen initially)
    depot = {
        x = SCREEN_WIDTH / 2,
        y = SCREEN_HEIGHT - 100,
        width = 80,
        height = 60
    }
    
    -- Track system
    tracks = {}
    track_map = {} -- Hash map for fast track lookup by position
    
    -- Train system
    trains = {}
    train_spawn_timer = 0
    TRAIN_SPAWN_INTERVAL = 3 -- seconds
    
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

function occupyPosition(x, y, train_id)
    local key = getPositionKey(x, y)
    occupied_positions[key] = train_id
end

function freePosition(x, y)
    local key = getPositionKey(x, y)
    occupied_positions[key] = nil
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
    camera.target_x = (mouse_x - SCREEN_WIDTH/2) * 0.5 -- Gentle mouse following
    camera.target_y = (mouse_y - SCREEN_HEIGHT/2) * 0.5
    
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
           math.abs(train.y - depot.y) < 20 then
            debugLog("REMOVING Train " .. train.id .. " - returned to depot")
            -- Free position if not at depot
            if not (train.x == depot.x and train.y == depot.y) then
                freePosition(train.x, train.y)
            end
            table.remove(trains, i)
        end
    end
end

function love.draw()
    -- Apply camera transform
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)
    
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
        local move_progress = train.move_timer / 0.5
        local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 10)
        
        if train.direction == -1 then
            -- Returning trains are blue
            if move_progress > 0.8 then
                love.graphics.setColor(0.1 * pulse, 0.1 * pulse, 0.8 * pulse) -- Pulsing blue
            else
                love.graphics.setColor(0.1, 0.1, 0.8) -- Blue when returning
            end
        else
            -- Outbound trains are red
            if move_progress > 0.8 then
                love.graphics.setColor(0.8 * pulse, 0.1 * pulse, 0.1 * pulse) -- Pulsing red
            else
                love.graphics.setColor(0.8, 0.1, 0.1) -- Red when going out
            end
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
    love.graphics.print("Move mouse to pan camera!", 10, 30)
    love.graphics.print("Trains: " .. #trains .. " | Tracks: " .. #tracks, 10, 50)
    love.graphics.print("Red=outbound, Blue=returning", 10, 70)
    
    -- Draw debug log panel in lower right
    drawDebugLogPanel()
end

function love.mousepressed(x, y, button)
    if button == 1 then -- Left click
        mouse_down = true
        -- Convert screen coordinates to world coordinates
        local world_x = x + camera.x
        local world_y = y + camera.y
        placeTrack(world_x, world_y)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if mouse_down then
        -- Convert screen coordinates to world coordinates
        local world_x = x + camera.x
        local world_y = y + camera.y
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
        -- Remove from path stack if present
        for i = #train.path_stack, 1, -1 do
            if train.path_stack[i] == track_to_remove then
                table.remove(train.path_stack, i)
            end
        end
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
    
    -- Spawn simple train at depot
    local train_id = math.floor(love.timer.getTime() * 100) -- Simpler ID for logging
    local target = depot_tracks[math.random(#depot_tracks)]
    local train = {
        id = train_id,
        x = depot.x,
        y = depot.y,
        target_track = target,
        current_track = nil, -- Track we're currently on
        came_from = nil, -- Track we came from (for dead end detection)
        direction = 1, -- 1 = outbound from depot, -1 = returning to depot
        move_timer = 0,
        path_stack = {} -- Stack of tracks for return journey
    }
    
    debugLog("Train " .. train.id .. " spawned at depot, targeting track at (" .. target.x .. "," .. target.y .. ")")
    table.insert(trains, train)
end

function updateTrain(train, dt)
    -- Update movement timer
    train.move_timer = train.move_timer + dt
    local MOVE_INTERVAL = 0.5 -- Move every 0.5 seconds
    
    -- Only attempt movement at discrete intervals
    if train.move_timer >= MOVE_INTERVAL then
        train.move_timer = 0
        
        local current_track_info = train.current_track and ("Track " .. train.current_track.id) or "Depot"
        debugLog("Train " .. train.id .. " attempting move. Direction: " .. train.direction .. " Current: (" .. train.x .. "," .. train.y .. ") on " .. current_track_info)
        
        -- Determine next position based on direction
        local target_x, target_y, target_track
        
        if train.direction == 1 then
            -- Going outbound: move to target_track or find next track
            if train.target_track then
                target_x = train.target_track.x
                target_y = train.target_track.y
                target_track = train.target_track
            else
                debugLog("Train " .. train.id .. " has no target while going outbound")
                return
            end
        else
            -- Returning: find the track that leads back toward depot
            if train.current_track then
                local back_track = findTrackBackToDepot(train)
                if back_track then
                    target_x = back_track.x
                    target_y = back_track.y
                    target_track = back_track
                else
                    -- Direct connection to depot or no path back
                    target_x = depot.x
                    target_y = depot.y
                    target_track = nil
                end
            else
                -- We're at depot, stay there
                target_x = depot.x
                target_y = depot.y
                target_track = nil
            end
        end
        
        -- Check for obstacles
        local should_reverse = false
        local reverse_reason = ""
        
        if target_track then
            -- Check if target track is occupied by another train
            if isPositionOccupied(target_x, target_y) then
                should_reverse = true
                reverse_reason = "collision with another train"
            -- Check for dead end (no connections except where we came from)
            elseif train.direction == 1 and not hasForwardConnection(target_track, train.current_track) then
                should_reverse = true
                reverse_reason = "dead end"
            end
        end
        
        -- Handle reversal
        if should_reverse then
            train.direction = -1 -- Start returning to depot
            debugLog("Train " .. train.id .. " reversing due to: " .. reverse_reason)
            return -- Don't move this turn, just reverse
        end
        
        -- Execute the move
        -- Free current position (unless at depot)
        if not (train.x == depot.x and train.y == depot.y) then
            freePosition(train.x, train.y)
        end
        
        -- Store where we came from before moving
        local previous_track = train.current_track
        
        -- Move to target position
        train.x = target_x
        train.y = target_y
        train.current_track = target_track
        train.came_from = previous_track
        local target_track_info = target_track and ("Track " .. target_track.id) or "Depot"
        debugLog("Train " .. train.id .. " moved to (" .. train.x .. "," .. train.y .. ") on " .. target_track_info)
        
        -- Occupy new position (unless it's depot)
        if target_track then
            occupyPosition(target_x, target_y, train.id)
        end
        
        -- Update path tracking and next target
        if train.direction == 1 then
            -- Going outbound: push previous track to stack and find next target
            if previous_track then
                table.insert(train.path_stack, previous_track)
                debugLog("Train " .. train.id .. " pushed track to stack, stack size: " .. #train.path_stack)
            end
            
            if target_track then
                local next_track = findNextTrack(train)
                train.target_track = next_track
                if not next_track then
                    debugLog("Train " .. train.id .. " will hit dead end next turn")
                end
            end
        else
            -- Going inbound: we've consumed a track from our return journey
            debugLog("Train " .. train.id .. " returning, stack size: " .. #train.path_stack)
        end
    end
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

function findTrackBackToDepot(train)
    if not train.current_track then return nil end
    
    -- Use the path stack to find the next track back
    if #train.path_stack > 0 then
        local next_track_back = train.path_stack[#train.path_stack]
        table.remove(train.path_stack) -- Pop the track from stack
        debugLog("Train " .. train.id .. " popped track from stack, returning to track " .. next_track_back.id .. ", stack size now: " .. #train.path_stack)
        return next_track_back
    end
    
    -- Stack is empty, check if current track connects to depot
    if train.current_track.connected_to_depot then
        debugLog("Train " .. train.id .. " on depot-connected track, heading to depot")
        return nil -- Signal to go to depot
    end
    
    -- Fallback: try to find any track that connects to depot
    for _, connected_track in ipairs(train.current_track.connections) do
        if connected_track.connected_to_depot then
            debugLog("Train " .. train.id .. " found depot connection via " .. connected_track.id)
            return connected_track
        end
    end
    
    -- No path back found
    debugLog("Train " .. train.id .. " ERROR: No path back to depot found!")
    return nil
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
