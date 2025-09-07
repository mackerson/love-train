-- Love Train - Refactored with Classes
local Camera = require('lib.camera')
local Train = require('lib.train')
local TrackManager = require('lib.track-manager')
local Pathfinder = require('lib.pathfinder')
local Depot = require('lib.depot')
local DebugLog = require('lib.debug-log')

-- Game objects
local camera
local track_manager
local pathfinder
local depot
local debug_log

-- Game state
local trains = {}
local occupied_positions = {} -- Format: [x_y] = train_id

-- Game constants
local SCREEN_WIDTH, SCREEN_HEIGHT
local WORLD_WIDTH, WORLD_HEIGHT
local GRID_SIZE = 40
local TRAIN_SPAWN_INTERVAL = 3 -- seconds

-- Input handling
local mouse_down = false
local last_placed_position = {x = nil, y = nil} -- Track debouncing

-- Utility function for smooth interpolation
function smoothstep(t)
    -- Smooth cubic interpolation (eases in and out)
    return t * t * (3 - 2 * t)
end

function love.load()
    -- Enable console on Windows for debugging
    if love.system.getOS() == "Windows" then
        love.window.showMessageBox("Debug", "Console enabled - check for debug output", "info")
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
    
    -- Initialize game objects
    camera = Camera:new(SCREEN_WIDTH, SCREEN_HEIGHT, WORLD_WIDTH, WORLD_HEIGHT)
    track_manager = TrackManager:new(GRID_SIZE)
    pathfinder = Pathfinder:new()
    depot = Depot:new(SCREEN_WIDTH / 2, SCREEN_HEIGHT - 100, 80, 60, GRID_SIZE)
    debug_log = DebugLog:new(SCREEN_WIDTH, SCREEN_HEIGHT, 20)
    
    -- Center camera on depot at startup
    camera:centerOn(depot.x, depot.y)
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
    -- Update camera
    camera:update(dt)
    
    -- Update track manager
    track_manager:update(dt)
    
    -- Update trains
    for i = #trains, 1, -1 do
        local train = trains[i]
        train:update(dt, depot, track_manager:getAllTracks(), occupied_positions, pathfinder, debug_log)
        
        -- Remove trains that have returned to depot
        if train.direction == -1 and 
           depot:isTrainAtDepot(train) and
           train.current_track == nil then
            debug_log:log("REMOVING Train " .. train.id .. " - returned to depot")
            -- Free any positions this train might still be occupying
            clearTrainFromAllPositions(train.id)
            table.remove(trains, i)
        
        -- Also remove trains that have been off-track for too long
        elseif train.state == "off_track" and train.off_track_timer > 10 then
            debug_log:log("REMOVING Train " .. train.id .. " - off track too long")
            clearTrainFromAllPositions(train.id)
            table.remove(trains, i)
        end
    end
end

function love.draw()
    -- Apply camera transform
    camera:push()
    
    -- Draw world grid (optional visual aid)
    love.graphics.setColor(0.15, 0.5, 0.15, 0.3) -- Faint green grid
    for x = -WORLD_WIDTH/2, WORLD_WIDTH/2, GRID_SIZE do
        love.graphics.line(x, -WORLD_HEIGHT/2, x, WORLD_HEIGHT/2)
    end
    for y = -WORLD_HEIGHT/2, WORLD_HEIGHT/2, GRID_SIZE do
        love.graphics.line(-WORLD_WIDTH/2, y, WORLD_WIDTH/2, y)
    end
    
    -- Draw depot connection range (visual aid)
    depot:drawConnectionRange()
    
    -- Draw depot
    depot:draw()
    
    -- Draw tracks
    track_manager:draw(depot)
    
    -- Draw trains
    for _, train in ipairs(trains) do
        train:draw(depot)
    end
    
    -- Reset camera transform
    camera:pop()
    
    -- Draw UI (not affected by camera)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("CLICK: Place/Remove tracks | SPACE: Spawn train | ESC: Quit | ↑↓: Scroll log", 10, 10)
    love.graphics.print("Move mouse to pan camera! | Mouse wheel: Zoom", 10, 30)
    love.graphics.print("Trains: " .. #trains .. " | Tracks: " .. track_manager:getTrackCount() .. " | Zoom: " .. string.format("%.1f", camera.zoom) .. "x", 10, 50)
    
    -- Count occupied positions for debugging
    local occupied_count = 0
    for _ in pairs(occupied_positions) do
        occupied_count = occupied_count + 1
    end
    love.graphics.print("Red=outbound, Blue=returning, Yellow=stopped, Magenta=off-track | Occupied: " .. occupied_count, 10, 70)
    
    -- Draw debug log panel in lower right
    debug_log:draw()
end

function love.mousepressed(x, y, button)
    if button == 1 then -- Left click
        mouse_down = true
        -- Convert screen coordinates to world coordinates accounting for zoom
        local world_x, world_y = camera:screenToWorld(x, y)
        local success, new_last_placed = track_manager:placeTrack(world_x, world_y, depot, last_placed_position)
        last_placed_position = new_last_placed
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if mouse_down then
        -- Convert screen coordinates to world coordinates accounting for zoom
        local world_x, world_y = camera:screenToWorld(x, y)
        local success, new_last_placed = track_manager:placeTrack(world_x, world_y, depot, last_placed_position)
        last_placed_position = new_last_placed
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
        debug_log:log("=== SPAWNED TRAIN ===")
    elseif key == "escape" then
        love.event.quit()
    elseif key == "up" then
        debug_log:scroll(-1)
    elseif key == "down" then
        debug_log:scroll(1)
    end
end

function love.wheelmoved(x, y)
    -- y > 0 = wheel up (zoom in), y < 0 = wheel down (zoom out)
    local mouse_x, mouse_y = love.mouse.getPosition()
    camera:zoom(y, mouse_x, mouse_y)
end

function spawnTrain()
    local train = depot:spawnTrain(track_manager:getAllTracks(), occupied_positions, debug_log)
    if train then
        table.insert(trains, train)
    end
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
        debug_log:log("Cleared position " .. position_key .. " previously occupied by train " .. train_id)
    end
end

