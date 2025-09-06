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
    
    -- Hand cart system - carts can share tracks bidirectionally
    
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

-- Hand cart collision detection functions
function findCartsAt(x, y)
    -- Find all carts at a specific position
    local carts_here = {}
    for _, cart in ipairs(trains) do
        if math.abs(cart.x - x) < 10 and math.abs(cart.y - y) < 10 then
            table.insert(carts_here, cart)
        end
    end
    return carts_here
end

function findCartCollisions(cart)
    -- Find any carts this cart would collide with at its target position
    if not cart.target_track then return {} end
    
    local collisions = {}
    for _, other_cart in ipairs(trains) do
        if other_cart ~= cart and other_cart.current_track == cart.target_track then
            table.insert(collisions, other_cart)
        end
    end
    return collisions
end

function findClosestDepotTrack(from_track)
    -- Find the depot track that's closest to the given track
    local closest_track = nil
    local closest_distance = math.huge
    
    for _, track in ipairs(tracks) do
        if track.connected_to_depot then
            local distance = math.sqrt((track.x - from_track.x)^2 + (track.y - from_track.y)^2)
            if distance < closest_distance then
                closest_distance = distance
                closest_track = track
            end
        end
    end
    
    if closest_track then
        -- Use A* to find path to closest depot track
        local path = findPathToDepot(from_track)
        if path and #path > 1 then
            -- Return first step in path
            return path[2] -- path[1] is current track
        end
    end
    
    return closest_track
end

function handleCartCollision(cart, other_cart)
    -- Hand cart collision behavior: same direction = link, opposite = bounce
    debugLog("Cart " .. cart.id .. " (dir:" .. cart.direction .. ") colliding with cart " .. other_cart.id .. " (dir:" .. other_cart.direction .. ")")
    
    if cart.direction == other_cart.direction then
        -- Same direction - wait for other cart to move
        debugLog("Cart " .. cart.id .. " waiting for " .. other_cart.id .. " (same direction)")
        cart.waiting = true
        -- Keep current target but don't move this cycle
    else
        -- Opposite directions - returning cart has priority
        if cart.direction == -1 then
            -- This cart is returning, other cart bounces
            debugLog("Cart " .. cart.id .. " (returning) has priority, cart " .. other_cart.id .. " should bounce")
            -- Force other cart to reverse
            other_cart.direction = -1
            other_cart.target_track = findClosestDepotTrack(other_cart.current_track)
        else
            -- This cart is outbound, it bounces
            debugLog("Cart " .. cart.id .. " (outbound) bouncing due to returning cart " .. other_cart.id)
            cart.direction = -1
            cart.target_track = findClosestDepotTrack(cart.current_track)
        end
    end
end

function getTrackAt(x, y)
    local key = x .. "_" .. y
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
           train.logical_x == depot.x and 
           train.logical_y == depot.y and
           train.current_track == nil then
            debugLog("REMOVING Cart " .. train.id .. " - returned to depot")
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
    love.graphics.print("Carts: " .. #trains .. " | Tracks: " .. #tracks .. " | Zoom: " .. string.format("%.1f", camera.zoom) .. "x", 10, 50)
    love.graphics.print("Red=outbound, Blue=returning | Hand cart system", 10, 70)
    
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
        debugLog("=== SPAWNED CART ===")
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
    local position_key = grid_x .. "_" .. grid_y
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
    local position_key = track_to_remove.x .. "_" .. track_to_remove.y
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
    
    -- No position cleanup needed in hand cart system
    
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
    
    -- Alternate between depot tracks clockwise
    last_depot_track_index = (last_depot_track_index % #depot_tracks) + 1
    local target = depot_tracks[last_depot_track_index]
    local train = {
        id = train_id,
        x = depot.x,
        y = depot.y,
        target_track = target,
        current_track = nil, -- Track we're currently on
        came_from = nil, -- Track we came from (for dead end detection)
        direction = 1, -- 1 = outbound from depot, -1 = returning to depot
        waiting = false, -- True when waiting for another cart
        -- Logical vs visual position separation
        logical_x = depot.x,
        logical_y = depot.y,
        move_timer = 0,
        move_progress = 0 -- 0 to 1, progress between logical positions
    }
    
    debugLog("Cart " .. train.id .. " spawned at depot, targeting branch " .. last_depot_track_index .. " at (" .. target.x .. "," .. target.y .. ")")
    table.insert(trains, train)
end

function updateTrain(train, dt)
    local MOVE_INTERVAL = 1.0 -- Logical movement every 1 second
    
    -- Update movement timer and visual interpolation
    train.move_timer = train.move_timer + dt
    train.move_progress = math.min(1.0, train.move_timer / MOVE_INTERVAL)
    
    -- Determine target logical position
    local target_logical_x, target_logical_y
    if train.target_track then
        target_logical_x = train.target_track.x
        target_logical_y = train.target_track.y
    elseif train.direction == -1 then
        -- Returning to depot
        target_logical_x = depot.x
        target_logical_y = depot.y
    else
        -- No target, stay at current logical position
        target_logical_x = train.logical_x
        target_logical_y = train.logical_y
    end
    
    -- Smooth visual interpolation between logical positions
    local t = smoothstep(train.move_progress)
    train.x = train.logical_x + (target_logical_x - train.logical_x) * t
    train.y = train.logical_y + (target_logical_y - train.logical_y) * t
    
    -- Handle logical movement at intervals
    if train.move_timer >= MOVE_INTERVAL then
        train.move_timer = 0
        train.move_progress = 0
        
        -- Don't move if waiting for another cart
        if train.waiting then
            debugLog("Cart " .. train.id .. " waiting, skipping movement")
            return
        end
        
        -- Check if we've reached the target logically
        if target_logical_x ~= train.logical_x or target_logical_y ~= train.logical_y then
            -- Move to target logical position
            train.logical_x = target_logical_x
            train.logical_y = target_logical_y
            
            -- Handle arrival at logical target
            handleTrainArrival(train)
        end
    end
end

function handleTrainArrival(train)
    local current_track_info = train.current_track and ("Track " .. train.current_track.id) or "Depot"
    debugLog("Cart " .. train.id .. " arrived. Direction: " .. train.direction .. " Logical: (" .. train.logical_x .. "," .. train.logical_y .. ") on " .. current_track_info)
    
    -- Store where we came from before moving
    local previous_track = train.current_track
    
    -- Update current track based on logical arrival position
    if train.target_track and train.logical_x == train.target_track.x and train.logical_y == train.target_track.y then
        -- Arrived at a track
        train.current_track = train.target_track
        train.came_from = previous_track
        debugLog("Cart " .. train.id .. " arrived at track " .. train.current_track.id)
    elseif train.logical_x == depot.x and train.logical_y == depot.y then
        -- Arrived at depot
        train.current_track = nil
        train.came_from = previous_track
        debugLog("Cart " .. train.id .. " arrived at depot")
        return -- Stay at depot
    end
    
    -- Hand cart behavior: explore until track ends or hits junction, then seek closest depot
    local next_target = nil
    
    if train.direction == 1 then
        -- Going outbound: explore until track ends or junction
        if train.current_track then
            next_target = findNextTrack(train)
            if not next_target then
                -- Track ends - reverse and seek closest depot
                train.direction = -1
                debugLog("Cart " .. train.id .. " reached track end, seeking depot")
                next_target = findClosestDepotTrack(train.current_track)
            end
        end
    else
        -- Returning: head toward closest depot
        if train.current_track then
            if train.current_track.connected_to_depot then
                next_target = nil -- Go directly to depot
                debugLog("Cart " .. train.id .. " taking direct route to depot")
            else
                next_target = findClosestDepotTrack(train.current_track)
            end
        end
    end
    
    -- Clear waiting state from previous cycle
    train.waiting = false
    
    -- Check for collisions and handle hand cart linking/bouncing
    if next_target then
        local colliding_carts = findCartCollisions(train)
        if #colliding_carts > 0 then
            handleCartCollision(train, colliding_carts[1])
            -- If cart is now waiting, don't change the target
            if train.waiting then
                next_target = train.target_track -- Keep original target
            else
                next_target = train.target_track -- May have been changed by collision
            end
        end
    end
    
    train.target_track = next_target
    local target_info = next_target and ("Track " .. next_target.id) or "Depot"
    debugLog("Cart " .. train.id .. " new target: " .. target_info)
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

