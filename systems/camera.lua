local Class = require('lib.base-class')
local WorldConfig = require('config.world-config')

local Camera = Class:extend()

-- Helper function for sign (since math.sign might not exist in older Lua)
local function sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

function Camera:set(screen_width, screen_height)
    self.x = 0
    self.y = 0
    self.target_x = 0
    self.target_y = 0
    self.smooth = 10
    self.zoom = 1.0
    self.min_zoom = 0.3
    self.max_zoom = 3.0
    self.is_dragging = false
    self.edge_pan_active = false

    self.screen_width = screen_width
    self.screen_height = screen_height
    self.world_width = WorldConfig.WORLD_PIXEL_WIDTH
    self.world_height = WorldConfig.WORLD_PIXEL_HEIGHT

    local depot_x, depot_y = WorldConfig.tileCenterToWorld(WorldConfig.DEPOT_TILE_X, WorldConfig.DEPOT_TILE_Y)
    self:centerOn(depot_x, depot_y)
end

function Camera:update(dt)
    self:updateEdgePanning(dt)

    self:clampToWorldBounds()

    self.x = self.x + (self.target_x - self.x) * self.smooth * dt
    self.y = self.y + (self.target_y - self.y) * self.smooth * dt
end

function Camera:updateEdgePanning(dt)
    local mouse_x, mouse_y = love.mouse.getPosition()
    local pan_dx, pan_dy = 0, 0

    if mouse_x <= WorldConfig.EDGE_PAN_ZONE then
        pan_dx = -WorldConfig.EDGE_PAN_SPEED * dt
    elseif mouse_x >= self.screen_width - WorldConfig.EDGE_PAN_ZONE then
        pan_dx = WorldConfig.EDGE_PAN_SPEED * dt
    end

    if mouse_y <= WorldConfig.EDGE_PAN_ZONE then
        pan_dy = -WorldConfig.EDGE_PAN_SPEED * dt
    elseif mouse_y >= self.screen_height - WorldConfig.EDGE_PAN_ZONE then
        pan_dy = WorldConfig.EDGE_PAN_SPEED * dt
    end

    if pan_dx ~= 0 or pan_dy ~= 0 then
        self.edge_pan_active = true
        self.target_x = self.target_x + pan_dx / self.zoom
        self.target_y = self.target_y + pan_dy / self.zoom
    else
        self.edge_pan_active = false
    end
end

function Camera:clampToWorldBounds()
    local half_screen_width = (self.screen_width / 2) / self.zoom
    local half_screen_height = (self.screen_height / 2) / self.zoom

    local min_x = half_screen_width
    local max_x = self.world_width - half_screen_width
    local min_y = half_screen_height
    local max_y = self.world_height - half_screen_height

    if max_x < min_x then
        self.target_x = self.world_width / 2
    else
        self.target_x = math.max(min_x, math.min(max_x, self.target_x))
    end

    if max_y < min_y then
        self.target_y = self.world_height / 2
    else
        self.target_y = math.max(min_y, math.min(max_y, self.target_y))
    end
end

function Camera:getVisibleTileBounds()
    local left = math.max(0, self.x - (self.screen_width / 2 / self.zoom))
    local top = math.max(0, self.y - (self.screen_height / 2 / self.zoom))
    local right = math.min(self.world_width, self.x + (self.screen_width / 2 / self.zoom))
    local bottom = math.min(self.world_height, self.y + (self.screen_height / 2 / self.zoom))

    local minTileX = math.floor(left / WorldConfig.TILE_SIZE)
    local minTileY = math.floor(top / WorldConfig.TILE_SIZE)
    local maxTileX = math.ceil(right / WorldConfig.TILE_SIZE)
    local maxTileY = math.ceil(bottom / WorldConfig.TILE_SIZE)

    return minTileX, minTileY, maxTileX, maxTileY
end

function Camera:isPointVisible(x, y)
    local sx, sy = self:worldToScreen(x, y)
    return sx >= -50 and sx <= self.screen_width + 50 and
           sy >= -50 and sy <= self.screen_height + 50
end

function Camera:pan(dx, dy)
    self.target_x = self.target_x + dx / self.zoom
    self.target_y = self.target_y + dy / self.zoom
    self:clampToWorldBounds()
end

function Camera:centerOn(x, y)
    self.target_x = x
    self.target_y = y
    self.x = x
    self.y = y
    self:clampToWorldBounds()
end

function Camera:screenToWorld(screen_x, screen_y)
    local world_x = (screen_x - self.screen_width/2) / self.zoom + self.x
    local world_y = (screen_y - self.screen_height/2) / self.zoom + self.y
    return world_x, world_y
end

function Camera:worldToScreen(world_x, world_y)
    local screen_x = (world_x - self.x) * self.zoom + self.screen_width/2
    local screen_y = (world_y - self.y) * self.zoom + self.screen_height/2
    return screen_x, screen_y
end

function Camera:zoomTowards(delta, mouse_x, mouse_y)
    local zoom_factor = 1.1
    local old_zoom = self.zoom

    if delta > 0 then
        self.zoom = math.min(self.max_zoom, self.zoom * zoom_factor)
    elseif delta < 0 then
        self.zoom = math.max(self.min_zoom, self.zoom / zoom_factor)
    end

    local world_x, world_y = self:screenToWorld(mouse_x, mouse_y)

    local scale_change = self.zoom / old_zoom
    self.x = world_x - (world_x - self.x) * scale_change
    self.y = world_y - (world_y - self.y) * scale_change
    self.target_x = self.x
    self.target_y = self.y

    self:clampToWorldBounds()
end

function Camera:push()
    love.graphics.push()
    love.graphics.translate(self.screen_width/2, self.screen_height/2)
    love.graphics.scale(self.zoom, self.zoom)
    love.graphics.translate(-self.x, -self.y)
end

function Camera:pop()
    love.graphics.pop()
end

return Camera
