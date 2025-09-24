local WorldConfig = {}

WorldConfig.WORLD_TILES_X = 100
WorldConfig.WORLD_TILES_Y = 100
WorldConfig.TILE_SIZE = 40

WorldConfig.WORLD_PIXEL_WIDTH = WorldConfig.WORLD_TILES_X * WorldConfig.TILE_SIZE
WorldConfig.WORLD_PIXEL_HEIGHT = WorldConfig.WORLD_TILES_Y * WorldConfig.TILE_SIZE

WorldConfig.EDGE_PAN_ZONE = 20
WorldConfig.EDGE_PAN_SPEED = 1200
WorldConfig.EDGE_PAN_ACCELERATION = 8

WorldConfig.DEPOT_TILE_X = 50
WorldConfig.DEPOT_TILE_Y = 50

function WorldConfig.tileToWorld(tx, ty)
    return tx * WorldConfig.TILE_SIZE, ty * WorldConfig.TILE_SIZE
end

function WorldConfig.worldToTile(wx, wy)
    return math.floor(wx / WorldConfig.TILE_SIZE), math.floor(wy / WorldConfig.TILE_SIZE)
end

function WorldConfig.tileCenterToWorld(tx, ty)
    local wx, wy = WorldConfig.tileToWorld(tx, ty)
    return wx + WorldConfig.TILE_SIZE / 2, wy + WorldConfig.TILE_SIZE / 2
end

function WorldConfig.isInWorldBounds(wx, wy)
    return wx >= 0 and wx < WorldConfig.WORLD_PIXEL_WIDTH and
           wy >= 0 and wy < WorldConfig.WORLD_PIXEL_HEIGHT
end

function WorldConfig.isInTileBounds(tx, ty)
    return tx >= 0 and tx < WorldConfig.WORLD_TILES_X and
           ty >= 0 and ty < WorldConfig.WORLD_TILES_Y
end

return WorldConfig