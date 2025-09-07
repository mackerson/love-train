local Class = require('lib.base-class')

local DebugLog = Class:extend()

function DebugLog:set(screen_width, screen_height, max_lines)
    self.messages = {}
    self.max_lines = max_lines or 20
    self.screen_width = screen_width
    self.screen_height = screen_height
    
    -- Panel settings
    self.panel = {
        width = 400,
        height = 200,
        margin = 10,
        line_height = 15,
        scroll_offset = 0,
        max_visible_lines = 12
    }
end

function DebugLog:log(message)
    print(message) -- Console output
    table.insert(self.messages, message)
    
    -- Keep only last max_lines
    if #self.messages > self.max_lines then
        table.remove(self.messages, 1)
    end
    
    -- Auto-scroll to bottom when new messages arrive
    self.panel.scroll_offset = math.max(0, #self.messages - self.panel.max_visible_lines)
end

function DebugLog:draw()
    local panel = self.panel
    local panel_x = self.screen_width - panel.width - panel.margin
    local panel_y = self.screen_height - panel.height - panel.margin
    
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
    local end_line = math.min(#self.messages, start_line + panel.max_visible_lines - 1)
    
    -- Draw log lines
    love.graphics.setColor(1, 1, 1) -- White for log text
    local text_y = panel_y + 25 -- Start below title
    
    for i = start_line, end_line do
        local log_line = self.messages[i]
        -- Truncate long lines to fit in panel
        if love.graphics.getFont():getWidth(log_line) > panel.width - 20 then
            log_line = string.sub(log_line, 1, 50) .. "..."
        end
        love.graphics.print(log_line, panel_x + 10, text_y)
        text_y = text_y + panel.line_height
    end
    
    -- Draw scrollbar if needed
    if #self.messages > panel.max_visible_lines then
        self:drawScrollbar(panel_x, panel_y)
    end
    
    -- Draw scroll instructions
    if #self.messages > panel.max_visible_lines then
        love.graphics.setColor(0.7, 0.7, 0.7) -- Gray for instructions
        love.graphics.print("↑↓ to scroll", panel_x + panel.width - 70, panel_y + panel.height - 15)
    end
end

function DebugLog:drawScrollbar(panel_x, panel_y)
    local panel = self.panel
    local scrollbar_x = panel_x + panel.width - 15
    local scrollbar_y = panel_y + 25
    local scrollbar_height = panel.height - 45
    
    -- Draw scrollbar track
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", scrollbar_x, scrollbar_y, 10, scrollbar_height)
    
    -- Calculate thumb position and size
    local total_lines = #self.messages
    local visible_ratio = panel.max_visible_lines / total_lines
    local thumb_height = math.max(20, scrollbar_height * visible_ratio)
    local scroll_ratio = panel.scroll_offset / (total_lines - panel.max_visible_lines)
    local thumb_y = scrollbar_y + scroll_ratio * (scrollbar_height - thumb_height)
    
    -- Draw scrollbar thumb
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    love.graphics.rectangle("fill", scrollbar_x, thumb_y, 10, thumb_height)
end

function DebugLog:scroll(direction)
    local panel = self.panel
    local max_scroll = math.max(0, #self.messages - panel.max_visible_lines)
    
    panel.scroll_offset = math.max(0, math.min(max_scroll, panel.scroll_offset + direction))
end

function DebugLog:clear()
    self.messages = {}
    self.panel.scroll_offset = 0
end

return DebugLog
