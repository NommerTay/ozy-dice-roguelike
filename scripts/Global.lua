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
--      brand-new custom d6 for the clicking player. The die is a real
--      TTS "Custom_Dice" object whose texture (all 6 faces baked into
--      one image, hosted in this repo) was composed at build time by
--      tools/generate_dice_textures.py - one finished die per legal
--      composition (Misses 1-2 | Attacks 1-3 | Defends 1-3 |
--      Statuses 0-2, totalling 6). A Custom_Dice texture can't be
--      composed at click-time (TTS Lua cannot stitch images), so the
--      button picks one of the pre-made dice at random, spawns it with
--      its texture straight from GitHub, and rolls it for the player.
--      The catalog of dice lives in data/dice_catalog.json.
--   3. When the die comes to rest, the top face (die value 1-6) is
--      looked up in that stored list and its effect is broadcast.
--   4. The second button, "Player Mat", spawns the Korts player board
--      for the clicking player as a real TTS "Custom_Tile" (a flat
--      rectangular tile) with the board art from this repo
--      (korts_player_board.png in the repo root). One mat per player:
--      clicking again replaces that player's old mat.
-- =====================================================================

-- Asset/database base URL for this repo (change only if you fork/rename it).
local GITHUB_RAW_BASE =
    "https://raw.githubusercontent.com/NommerTay/ozy-dice-roguelike/main/"
local DATABASE_URL = GITHUB_RAW_BASE .. "data/face_database.json"
local CATALOG_URL  = GITHUB_RAW_BASE .. "data/dice_catalog.json"
local BOARD_IMAGE_URL = GITHUB_RAW_BASE .. "korts_player_board.png"

local POOL_LABEL = {
    misses = "Miss", attacks = "Attack", defends = "Defend", statuses = "Status",
}

-- A Custom_Dice spawned with type=1 gets standard d6 rotation values
-- from TTS itself (that is what tells getValue() which face is up).
-- The dice textures were composed to match those values: in the die's
-- local space 1=+Z, 2=+Y, 3=-X, 4=+X, 5=-Y, 6=-Z (opposites sum to 7),
-- derived from real Custom_Dice save files - see VALUE_TO_CELL in
-- tools/generate_dice_textures.py. If a roll ever announces a different
-- face than the icon showing on top, that map is the place to permute.

local FaceDatabase = nil   -- filled by the GitHub download, or the fallback
local DiceCatalog  = nil   -- filled by the GitHub download, or the fallback
local BuiltDice    = {}    -- guid -> { faces = {...}, owner = color }
local SpawnedMats  = {}    -- player color -> guid of their current mat

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

    log("[CozyDice] Loading dice catalog from GitHub...")
    WebRequest.get(CATALOG_URL, function(request)
        if request.is_error or request.text == nil or request.text == "" then
            log("[CozyDice] Catalog download failed - using embedded fallback catalog.")
            DiceCatalog = EMBEDDED_CATALOG
        else
            local ok, decoded = pcall(JSON.decode, request.text)
            if ok and decoded and decoded.dice and #decoded.dice > 0 then
                DiceCatalog = decoded.dice
                log("[CozyDice] Dice catalog loaded: " .. #DiceCatalog .. " dice.")
            else
                log("[CozyDice] Catalog JSON did not parse - using fallback catalog.")
                DiceCatalog = EMBEDDED_CATALOG
            end
        end
    end)
end

-- ---------------------------------------------------------------------
-- The Roll button (called from UI.xml: onClick="onRollClicked")
-- TTS UI handlers receive (player, value, id).
-- ---------------------------------------------------------------------
function onRollClicked(player, _, _)
    if FaceDatabase == nil or DiceCatalog == nil then
        broadcastToColor("The dice workshop is still warming up - try again in a second!",
            player.color, { 0.95, 0.55, 0.45 })
        return
    end
    buildCustomDie(player)
end

-- ---------------------------------------------------------------------
-- Catalog faces are stored as ids; resolve them against the face
-- database to get names / values / effects for the die's description
-- and the roll broadcast. Falls back to a stub if an id is unknown
-- (e.g. the embedded database is in use and has fewer faces).
-- ---------------------------------------------------------------------
local function resolveFaces(entry)
    local byId = {}
    if FaceDatabase and FaceDatabase.pools then
        for poolName, pool in pairs(FaceDatabase.pools) do
            for _, face in ipairs(pool) do
                byId[face.id] = {
                    id = face.id, pool = poolName, name = face.name,
                    value = face.value, effect = face.effect,
                }
            end
        end
    end
    local faces = {}
    for _, id in ipairs(entry.faces) do
        table.insert(faces, byId[id] or
            { id = id, pool = "misses", name = id, value = 0, effect = "" })
    end
    return faces
end

local function countPools(faces)
    local counts = { misses = 0, attacks = 0, defends = 0, statuses = 0 }
    for _, face in ipairs(faces) do
        if counts[face.pool] ~= nil then counts[face.pool] = counts[face.pool] + 1 end
    end
    return counts
end

-- ---------------------------------------------------------------------
-- Build the die
-- ---------------------------------------------------------------------
local function describeFaces(faces)
    local lines = { "Faces on this die (by die value):" }
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
    -- Pick one of the pre-made dice from the catalog. Each catalog die
    -- already obeys the composition rules (see the generator script).
    local entry = DiceCatalog[math.random(#DiceCatalog)]
    local faces = resolveFaces(entry)  -- faces[i] sits on die value i
    local counts = countPools(faces)
    local spawnPos = getSpawnPosition(player)

    broadcastToColor(string.format(
        "Building your die: %d Miss / %d Attack / %d Defend / %d Status",
        counts.misses, counts.attacks, counts.defends, counts.statuses),
        player.color, { 1, 0.9, 0.6 })

    -- Spawn a genuine Custom_Dice object (the "custom die" item type)
    -- using the API's documented pattern: spawnObject with the custom
    -- type name, then setCustomObject with the texture + die type.
    -- (V3.0 tried spawnObjectData with a hand-built data table; TTS
    -- rejected it with "failed to load - object reference not set",
    -- Ben's test 2026-10-22. The data-table route needs fields that
    -- are only reliably produced by getData() on a real object.)
    local die = spawnObject({
        type = "Custom_Dice",
        position = spawnPos,
        rotation = { 0, math.random(360), 0 },
        scale = { 1.4, 1.4, 1.4 },  -- chunkier die, so the face icons read well
        sound = true,
        callback_function = function(spawned)
            spawned.setName("Cozy Die - " .. playerDisplayName(player))
            spawned.setDescription(describeFaces(faces))
            spawned.setGMNotes(JSON.encode(faces))
            BuiltDice[spawned.getGUID()] = { faces = faces, owner = player.color,
                                             ownerName = playerDisplayName(player) }
            spawned.randomize(player.color)
        end,
    })
    if die then
        die.setCustomObject({
            image = GITHUB_RAW_BASE .. entry.texture,
            type = 1,  -- 1 = six-sided
        })
    end
end


-- ---------------------------------------------------------------------
-- The Player Mat button (called from UI.xml: onClick="onMatClicked")
-- ---------------------------------------------------------------------
function onMatClicked(player, _, _)
    spawnPlayerMat(player)
end

function spawnPlayerMat(player)
    -- One mat per player: replace their old mat instead of piling up.
    local oldGuid = SpawnedMats[player.color]
    if oldGuid then
        local old = getObjectFromGUID(oldGuid)
        if old then old.destruct() end
        SpawnedMats[player.color] = nil
    end

    -- Spawn spot: same place the dice use, but down on the table -
    -- getSpawnPosition aims 3 units up for tossing dice.
    local pos = getSpawnPosition(player)
    local matPos = { pos[1], 2, pos[3] }

    -- A genuine TTS "Custom_Tile" (the custom tile item type), using
    -- the same documented pattern as the dice: spawnObject with the
    -- custom type name, then setCustomObject with the image.
    -- Tile type 0 = rectangle. The board art is 1920x1280 (3:2) and a
    -- custom tile's footprint is square at scale 1, so an x:z scale of
    -- 3:2 keeps the art undistorted. To resize the mat, change
    -- MAT_SCALE - keep the 3:2 ratio.
    local MAT_SCALE = { 6, 1, 4 }
    local mat = spawnObject({
        type = "Custom_Tile",
        position = matPos,
        rotation = { 0, 0, 0 },
        scale = MAT_SCALE,
        sound = true,
        callback_function = function(spawned)
            spawned.setName("Korts Player Mat - " .. playerDisplayName(player))
            spawned.setDescription("The Korts player board: faction info, " ..
                "starting dice, and the mine's active dice, treasures " ..
                "and artifacts.")
            SpawnedMats[player.color] = spawned.getGUID()
        end,
    })
    if mat then
        mat.setCustomObject({
            image = BOARD_IMAGE_URL,
            type = 0,          -- 0 = rectangle tile
            stackable = false,
        })
    end
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
    for color, guid in pairs(SpawnedMats) do
        if guid == object.getGUID() then SpawnedMats[color] = nil end
    end
end

-- =====================================================================
-- EMBEDDED FALLBACK DATABASE
-- A shortened copy of data/face_database.json (2 faces per pool) so the
-- Roll button still works before GitHub is set up, or if it is down.
-- The GitHub file is the real database - keep new faces there.
-- =====================================================================
-- Fallback catalog (first two dice) if the GitHub catalog can't load.
-- Faces are ids in value order 1..6, matching data/dice_catalog.json.
EMBEDDED_CATALOG = {
    { id = "dice_01", texture = "dice_01.png",
      faces = { "status_burn", "block_1", "negate",
                "break", "status_corrupt", "crit" } },
    { id = "dice_02", texture = "dice_02.png",
      faces = { "block_1", "status_corrupt", "negate",
                "miss", "block_1", "hit_1" } },
}

EMBEDDED_DATABASE = {
    version = 2,
    pools = {
        misses = {
            { id = "miss", name = "Miss", value = 0,
              effect = "Nothing happens.",
              icon = "miss.png" },
            { id = "chip", name = "Chip", value = 0,
              effect = "The die loses value: a random non-Miss side of it is turned into a Miss.",
              icon = "chip.png" },
        },
        attacks = {
            { id = "hit_1", name = "Hit +1", value = 1,
              effect = "Succeeds the roll: a hit worth 1.",
              icon = "hit_1.png" },
            { id = "crit", name = "Crit", value = 2,
              effect = "Double the amount of one of your Hits rolled.",
              icon = "crit.png" },
        },
        defends = {
            { id = "block_1", name = "Block +1", value = 1,
              effect = "Ignores one die from the Attack pool targeting you. Block strength 1.",
              icon = "block_1.png" },
            { id = "negate", name = "Negate", value = 1,
              effect = "Ignores one die from the Status pool targeting you.",
              icon = "negate.png" },
        },
        statuses = {
            { id = "status_burn", name = "Burn", value = 1,
              effect = "Status: Burn. (Effect to be defined.)",
              icon = "status_burn.png" },
            { id = "status_daze", name = "Daze", value = 1,
              effect = "Status: Daze. (Effect to be defined.)",
              icon = "status_daze.png" },
        },
    },
}
