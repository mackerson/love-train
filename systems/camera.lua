local Class = require('lib.base-class')

local Camera = Class:extend()

function Camera:set(screen_width, screen_height, world_width, world_height)
    self.x = 0
    self.y = 0
    self.target_x = 0
    self.target_y = 0
    self.smooth = 5 -- Camera smoothing factor
    self.zoom = 1.0 -- Current zoom level
    self.min_zoom = 0.3
    self.max_zoom = 3.0
    self.is_dragging = false -- Track if user is actively moving camera

    -- Store dimensions for bounds checking
    self.screen_width = screen_width
    self.screen_height = screen_height
    self.world_width = world_width
    self.world_height = world_height
end

function Camera:update(dt)
    -- Update camera to follow mouse for now (can be changed later)
    local mouse_x, mouse_y = love.mouse.getPosition()
    self.target_x = (mouse_x - self.screen_width/2) * 0.5 / self.zoom -- Gentle mouse following adjusted for zoom
    self.target_y = (mouse_y - self.screen_height/2) * 0.5 / self.zoom
    
    -- Clamp camera to world bounds
    self.target_x = math.max(-self.world_width/2 + self.screen_width/2, 
                            math.min(self.world_width/2 - self.screen_width/2, self.target_x))
    self.target_y = math.max(-self.world_height/2 + self.screen_height/2, 
                            math.min(self.world_height/2 - self.screen_height/2, self.target_y))
    
    -- Smooth camera movement
    self.x = self.x + (self.target_x - self.x) * self.smooth * dt
    self.y = self.y + (self.target_y - self.y) * self.smooth * dt
end

function Camera:pan(dx, dy)
    -- Manual camera panning
    self.target_x = self.target_x + dx / self.zoom
    self.target_y = self.target_y + dy / self.zoom

    -- Clamp camera to world bounds
    self.target_x = math.max(-self.world_width/2 + self.screen_width/(2*self.zoom),
                            math.min(self.world_width/2 - self.screen_width/(2*self.zoom), self.target_x))
    self.target_y = math.max(-self.world_height/2 + self.screen_height/(2*self.zoom),
                            math.min(self.world_height/2 - self.screen_height/(2*self.zoom), self.target_y))
end

function Camera:centerOn(x, y)
    self.x = x - self.screen_width / 2
    self.y = y - self.screen_height / 2
    self.target_x = self.x
    self.target_y = self.y
end

function Camera:screenToWorld(screen_x, screen_y)
    -- Convert screen coordinates to world coordinates accounting for zoom
    local world_x = screen_x / self.zoom + self.x
    local world_y = screen_y / self.zoom + self.y
    return world_x, world_y
end

function Camera:worldToScreen(world_x, world_y)
    -- Convert world coordinates to screen coordinates accounting for zoom
    local screen_x = (world_x - self.x) * self.zoom
    local screen_y = (world_y - self.y) * self.zoom
    return screen_x, screen_y
end

function Camera:zoom(delta, mouse_x, mouse_y)
    -- delta > 0 = zoom in, delta < 0 = zoom out
    local zoom_factor = 1.1
    local old_zoom = self.zoom
    
    if delta > 0 then
        self.zoom = math.min(self.max_zoom, self.zoom * zoom_factor)
    elseif delta < 0 then
        self.zoom = math.max(self.min_zoom, self.zoom / zoom_factor)
    end
    
    -- Adjust camera position to zoom toward mouse cursor
    local world_x = mouse_x + self.x
    local world_y = mouse_y + self.y
    
    local zoom_ratio = self.zoom / old_zoom
    self.x = world_x - (world_x - self.x) * zoom_ratio
    self.y = world_y - (world_y - self.y) * zoom_ratio
    self.target_x = self.x
    self.target_y = self.y
end

function Camera:push()
    love.graphics.push()
    love.graphics.translate(-self.x, -self.y)
    love.graphics.scale(self.zoom, self.zoom)
end

function Camera:pop()
    love.graphics.pop()
end

return Camera
