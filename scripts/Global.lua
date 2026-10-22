-- =====================================================================
-- Cozy Dice Roguelike - Global.lua
-- Paste into: Modding > Scripting > Global (Lua tab) in Tabletop Simulator.
-- The matching button lives in scripts/UI.xml (Global > UI tab).
--
-- WHAT IT DOES
--   1. On load, downloads data/face_database.json from this GitHub repo
--      (4 pools x 5 faces: Misses, Attacks, Defends, Statuses).
--      If the download fails, it falls back to the small embedded copy
--      at the bottom of this file, so the table still works offline.
--   2. Clicking the "Roll" button (bottom of the Global UI) builds a
--      brand-new custom d6 for the clicking player:
--        * rolls a face composition inside these ranges, totalling 6:
--            Misses 1-2 | Attacks 1-3 | Defends 1-3 | Statuses 0-2
--        * picks that many faces at random from each pool
--        * spawns a d6, paints each chosen face icon on it as a decal
--          (loaded straight from the GitHub raw URLs), stores the six
--          faces in the die's GM Notes, names/describes the die, and
--          rolls it in front of the player.
--   3. When the die comes to rest, the top face (die value 1-6) is
--      looked up in that stored list and its effect is broadcast.
-- =====================================================================

-- Asset/database base URL for this repo (change only if you fork/rename it).
local GITHUB_RAW_BASE =
    "https://raw.githubusercontent.com/NommerTay/ozy-dice-roguelike/main/"
local DATABASE_URL = GITHUB_RAW_BASE .. "data/face_database.json"

-- Composition ranges, straight from the design brief (must total 6).
local COMPOSITION = {
    misses   = { min = 1, max = 2 },
    attacks  = { min = 1, max = 3 },
    defends  = { min = 1, max = 3 },
    statuses = { min = 0, max = 2 },
}
local DIE_SIDES = 6

local POOL_LABEL = {
    misses = "Miss", attacks = "Attack", defends = "Defend", statuses = "Status",
}

-- Face frames for the 6 values of a standard TTS Die_6.
-- Index = die value (what getValue() returns when that face is on top).
-- `normal` points out of that face; `rotation` orients a decal plane to
-- lie flat on the face, facing outward (a decal's default plane faces
-- +Z, so the top face needs rotation {90,0,0} to face +Y, etc.).
--
-- Why not TTS "Custom Dice"? A custom die takes ONE pre-composed texture
-- image (a template with all 6 faces baked in). Our faces are drafted at
-- click-time, and Lua inside TTS cannot composite images - that would
-- need a live image server. Decals are the runtime way to skin a die.
--
-- V2 calibration note: V1 hard-coded positions for a 1-unit die and the
-- decals exploded out around it (Ben's screenshot, 2026-10-22). The
-- built-in Die_6 mesh is much smaller than 1 unit, so placement is now
-- measured from the die's own bounds at runtime (applyFaceDecals below).
local FACE_FRAMES = {
    [1] = { normal = { 0,  1,  0 }, rotation = { 90,  0,   0   } }, -- top
    [6] = { normal = { 0, -1,  0 }, rotation = { -90, 0,   0   } }, -- bottom (opp. 1)
    [2] = { normal = { 0,  0,  1 }, rotation = { 0,   0,   0   } }, -- front
    [5] = { normal = { 0,  0, -1 }, rotation = { 0,   180, 0   } }, -- back   (opp. 2)
    [3] = { normal = { 1,  0,  0 }, rotation = { 0,   90,  0   } }, -- right
    [4] = { normal = { -1, 0,  0 }, rotation = { 0,   270, 0   } }, -- left   (opp. 3)
}

-- Paint the 6 drafted faces onto a spawned die as decals, sized from
-- the die's own measured bounds so this works whatever scale it is.
local function applyFaceDecals(die, faces)
    local bounds = die.getBoundsNormalized()  -- world size, rotation ignored
    local scale  = die.getScale()
    -- Convert world size into the die's local units (decals live in
    -- local space): local size = world size / object scale.
    local localSize = bounds.x / math.max(scale.x, 0.01)
    local half = localSize / 2

    for value, face in ipairs(faces) do
        local f = FACE_FRAMES[value]
        die.addDecal({
            name = face.id,
            url = face.icon_url,
            position = {
                f.normal[1] * (half + 0.02),
                f.normal[2] * (half + 0.02),
                f.normal[3] * (half + 0.02),
            },
            rotation = f.rotation,
            scale = localSize * 0.96,
        })
    end

    log(string.format(
        "[CozyDice] Die bounds %.2f, local size %.2f - decals applied.",
        bounds.x, localSize))
end

local FaceDatabase = nil   -- filled by the GitHub download, or the fallback
local BuiltDice    = {}    -- guid -> { faces = {...}, owner = color }

-- ---------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------
function onLoad()
    log("[CozyDice] Loading face database from GitHub...")
    WebRequest.get(DATABASE_URL, function(request)
        if request.is_error or request.text == nil or request.text == "" then
            log("[CozyDice] GitHub download failed (" ..
                (request.error or "empty response") ..
                ") - using the embedded fallback database.")
            FaceDatabase = EMBEDDED_DATABASE
        else
            local ok, decoded = pcall(JSON.decode, request.text)
            if ok and decoded and decoded.pools then
                FaceDatabase = decoded
                log("[CozyDice] Face database loaded from GitHub.")
            else
                log("[CozyDice] Database JSON did not parse - using fallback.")
                FaceDatabase = EMBEDDED_DATABASE
            end
        end
    end)
end

-- ---------------------------------------------------------------------
-- The Roll button (called from UI.xml: onClick="onRollClicked")
-- TTS UI handlers receive (player, value, id).
-- ---------------------------------------------------------------------
function onRollClicked(player, _, _)
    if FaceDatabase == nil then
        broadcastToColor("The dice workshop is still warming up - try again in a second!",
            player.color, { 0.95, 0.55, 0.45 })
        return
    end
    buildCustomDie(player)
end

-- ---------------------------------------------------------------------
-- Composition: pick counts inside the ranges that sum to exactly 6.
-- Start at every minimum, then hand out the remaining sides one at a
-- time to a random pool that still has room under its maximum.
-- ---------------------------------------------------------------------
local function rollComposition()
    local counts, total = {}, 0
    for pool, range in pairs(COMPOSITION) do
        counts[pool] = range.min
        total = total + range.min
    end

    local remaining = DIE_SIDES - total
    while remaining > 0 do
        local eligible = {}
        for pool, range in pairs(COMPOSITION) do
            if counts[pool] < range.max then table.insert(eligible, pool) end
        end
        if #eligible == 0 then break end  -- ranges can't reach 6: stop safely
        local chosen = eligible[math.random(#eligible)]
        counts[chosen] = counts[chosen] + 1
        remaining = remaining - 1
    end
    return counts
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- Pick n distinct faces from one pool (pools have 5, we need at most 3).
local function pickFaces(poolName, n)
    if n <= 0 then return {} end
    local picks, pool = {}, shuffle({ table.unpack(FaceDatabase.pools[poolName]) })
    for i = 1, math.min(n, #pool) do
        local face = pool[i]
        table.insert(picks, {
            id = face.id, pool = poolName, name = face.name,
            value = face.value, effect = face.effect,
            icon_url = GITHUB_RAW_BASE .. face.icon,
        })
    end
    return picks
end

-- ---------------------------------------------------------------------
-- Build the die
-- ---------------------------------------------------------------------
local function describeFaces(faces)
    local lines = { "This die was drafted just now:" }
    for value, face in ipairs(faces) do
        table.insert(lines, string.format("%d. [%s] %s (%s) - %s",
            value, POOL_LABEL[face.pool], face.name, tostring(face.value), face.effect))
    end
    return table.concat(lines, "\n")
end

local function tintForPool(pool)
    if pool == "attacks"  then return { 0.95, 0.45, 0.40 } end
    if pool == "defends"  then return { 0.45, 0.70, 0.45 } end
    if pool == "statuses" then return { 0.65, 0.55, 0.90 } end
    return { 0.75, 0.75, 0.75 }  -- misses: soft grey, no drama
end

-- ---------------------------------------------------------------------
-- Helpers for finding the player / a spawn spot.
-- NOTE (fixed after Ben's first in-TTS test): Player.getPlayerHandTransform
-- does not exist in current TTS - calling it threw
-- "can't access field getPlayerHandTransform of userdataLuaPlayer".
-- The hand-transform call differs between TTS versions, so every method
-- is tried inside pcall and ANY failure falls back safely instead of
-- killing the whole Roll click.
-- ---------------------------------------------------------------------
local function playerDisplayName(player)
    local ok, name = pcall(function()
        local p = Player[player.color]
        return p and p.steam_name
    end)
    if ok and name and name ~= "" then return name end
    return player.color
end

local SEAT_ORDER = { "White", "Brown", "Red", "Orange", "Yellow", "Green",
                     "Teal", "Blue", "Purple", "Pink", "Grey", "Black" }

local function getSpawnPosition(player)
    local p = Player[player.color]

    -- Try the known hand-transform spellings for this TTS version.
    local ok, pos = pcall(function()
        local t = nil
        if p.getHandTransform then t = p.getHandTransform()
        elseif p.getPlayerHandTransform then t = p.getPlayerHandTransform() end
        if t and t.position then
            return { t.position.x, t.position.y + 3, t.position.z }
        end
        return nil
    end)
    if ok and pos then return pos end

    -- Next best: above the first object sitting in the player's hand.
    local ok2, pos2 = pcall(function()
        local hand = p.getHandObjects(1)
        if hand and hand[1] then
            local hp = hand[1].getPosition()
            return { hp.x, hp.y + 3, hp.z }
        end
        return nil
    end)
    if ok2 and pos2 then return pos2 end

    -- Fallback: a ring around the table centre, one slot per seat colour,
    -- so different players' dice don't all land in the same spot.
    local slot = 1
    for i, color in ipairs(SEAT_ORDER) do
        if color == player.color then slot = i break end
    end
    local angle = math.rad((slot - 1) * (360 / #SEAT_ORDER))
    return { 6 * math.sin(angle), 3, 6 * math.cos(angle) }
end

function buildCustomDie(player)
    local counts = rollComposition()

    local faces = {}
    for _, poolName in ipairs({ "misses", "attacks", "defends", "statuses" }) do
        for _, face in ipairs(pickFaces(poolName, counts[poolName])) do
            table.insert(faces, face)
        end
    end
    shuffle(faces)  -- so pool order doesn't predict which value lands where

    local spawnPos = getSpawnPosition(player)

    broadcastToColor(string.format(
        "Building your die: %d Miss / %d Attack / %d Defend / %d Status",
        counts.misses, counts.attacks, counts.defends, counts.statuses),
        player.color, { 1, 0.9, 0.6 })

    spawnObject({
        type = "Die_6",
        position = spawnPos,
        rotation = { 0, math.random(360), 0 },
        scale = { 1.5, 1.5, 1.5 },  -- chunkier die, so the face icons read well
        sound = true,
        callback_function = function(die)
            -- faces[i] is the face that reads as value i once at rest.
            die.setName("Cozy Die - " .. playerDisplayName(player))
            die.setDescription(describeFaces(faces))
            die.setGMNotes(JSON.encode(faces))
            die.setColorTint({ 1, 0.99, 0.95 })

            applyFaceDecals(die, faces)

            BuiltDice[die.getGUID()] = { faces = faces, owner = player.color,
                                         ownerName = playerDisplayName(player) }
            die.randomize(player.color)
        end,
    })
end


-- ---------------------------------------------------------------------
-- Resolving a roll: when one of our built dice stops, announce the
-- face on top. getValue() -> index into the stored face list.
-- ---------------------------------------------------------------------
function onObjectRandomize(object, playerColor)
    local record = BuiltDice[object.getGUID()]
    if not record then return end

    Wait.condition(function()
        local value = object.getValue()
        local face = record.faces[value]
        if not face then return end
        broadcastToAll(string.format("%s rolled %s [%s] - %s",
            record.ownerName or record.owner, face.name,
            POOL_LABEL[face.pool], face.effect),
            tintForPool(face.pool))
    end, function()
        return object.resting
    end)
end


-- Tidy up tracking when a built die is destroyed / put away.
function onObjectDestroy(object)
    BuiltDice[object.getGUID()] = nil
end

-- =====================================================================
-- EMBEDDED FALLBACK DATABASE
-- A shortened copy of data/face_database.json (2 faces per pool) so the
-- Roll button still works before GitHub is set up, or if it is down.
-- The GitHub file is the real database - keep new faces there.
-- =====================================================================
EMBEDDED_DATABASE = {
    version = 0,
    pools = {
        misses = {
            { id = "miss_cloud", name = "Drifting Cloud", value = 0,
              effect = "Nothing happens. Take a breath.",
              icon = "miss_cloud.png" },
            { id = "miss_dropped_mug", name = "Dropped Mug", value = 0,
              effect = "Your cocoa spills. No effect.",
              icon = "miss_dropped_mug.png" },
        },
        attacks = {
            { id = "attack_wooden_sword", name = "Wooden Sword", value = 2,
              effect = "Deal 2 damage.",
              icon = "attack_wooden_sword.png" },
            { id = "attack_ember", name = "Ember Pop", value = 3,
              effect = "Deal 3 damage.",
              icon = "attack_ember.png" },
        },
        defends = {
            { id = "defend_wooden_shield", name = "Wooden Shield", value = 2,
              effect = "Block 2 damage this round.",
              icon = "defend_wooden_shield.png" },
            { id = "defend_knitted_blanket", name = "Knitted Blanket", value = 1,
              effect = "Block 1 damage and feel cozy: heal 1 if unharmed.",
              icon = "defend_knitted_blanket.png" },
        },
        statuses = {
            { id = "status_bloom", name = "Bloom", value = 1,
              effect = "Apply Bloom: heal 1 at the start of your next 2 turns.",
              icon = "status_bloom.png" },
            { id = "status_chill", name = "Chill", value = 1,
              effect = "Apply Chill: target's next Attack deals 1 less damage.",
              icon = "status_chill.png" },
        },
    },
}
