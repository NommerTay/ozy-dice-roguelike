-- =====================================================================
-- Cozy Dice Roguelike - CustomDie.lua  (OPTIONAL, alternative pattern)
--
-- Global.lua builds dice on its own, so you do NOT need this script.
-- Use this version instead if you'd rather place ONE template custom
-- die on the table (e.g. your own cozy die mesh) and have the Roll
-- button clone it: put this script on that template die, and in
-- Global.lua swap spawnObject({ type = "Die_6", ... }) for a clone:
--
--     local die = templateDie.clone({ position = spawnPos })
--
-- This script reads the six drafted faces from the die's own GM Notes
-- (written by Global.lua when the die was built) and, whenever this
-- die is rolled and comes to rest, announces its own top face.
-- It needs no database of its own - the faces travel with the die,
-- so a saved game / saved object keeps the exact die it was built as.
-- =====================================================================

local faces = nil

function onLoad()
    local notes = self.getGMNotes()
    if notes and notes ~= "" then
        local ok, decoded = pcall(JSON.decode, notes)
        if ok then faces = decoded end
    end
end

-- Called by Global.lua right after cloning, before the roll.
function setFaces(newFaces)
    faces = newFaces
    self.setGMNotes(JSON.encode(newFaces))
end

function onRandomize(playerColor)
    Wait.condition(function()
        if not faces then return end
        local face = faces[self.getValue()]
        if not face then return end
        broadcastToAll(string.format("%s - top face: %s - %s",
            self.getName(), face.name, face.effect), { 1, 0.9, 0.6 })
    end, function()
        return self.resting
    end)
end
