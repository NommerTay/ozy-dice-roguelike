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
--      (the board PNG in the repo root). One mat per player:
--      clicking again replaces that player's old mat.
--   5. Each spawned mat carries a small object script (generated
--      below) that puts an INVISIBLE click zone over every printed
--      Starting Dice slot on the board. Clicking a slot calls back
--      into this Global script (spawnStartingDie), which places the
--      slot's die on that exact spot on the mat: combat slots pick a
--      matching die from the catalog (DEF = most Defends, ATK = most
--      Attacks, DAZE = a die containing the Daze face); the Event and
--      Faction dice are not designed yet, so those slots spawn a
--      clearly-labelled stand-in die for now. Clicking a slot again
--      replaces its previous die.
-- =====================================================================

-- Asset/database base URL for this repo (change only if you fork/rename it).
local GITHUB_RAW_BASE =
    "https://raw.githubusercontent.com/NommerTay/ozy-dice-roguelike/main/"
local DATABASE_URL = GITHUB_RAW_BASE .. "data/face_database.json"
local CATALOG_URL  = GITHUB_RAW_BASE .. "data/dice_catalog.json"
-- NOTE: this must match the board file's name in the repo root
-- EXACTLY - a wrong name makes TTS report "Load Image failed" and
-- spawn a blank white tile. The PNG is fully opaque on purpose:
-- TTS tiles flatten transparency to grey, so the board's backdrop
-- is painted in (the scenery extended outward) instead of alpha.
local BOARD_IMAGE_URL = GITHUB_RAW_BASE .. "korts_board.png"

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
local MatSlotDice  = {}    -- mat guid -> { slot id -> die guid }
local buildMatScript  -- forward declaration: defined with the slot
                      -- system further down (Lua locals are only
                      -- visible AFTER their declaration line).

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
    -- Tile type 0 = rectangle. The board PNG is the shaped board
    -- cropped tight (4096x3487, ~1.18:1) with the backdrop knocked
    -- out to transparency, and a custom tile's footprint is square at
    -- scale 1, so an x:z scale of ~1.18 keeps the art undistorted.
    -- To resize the mat, change MAT_SCALE - keep the ~1.18 ratio.
    local MAT_SCALE = { 7.05, 1, 6 }
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
            spawned.setLuaScript(buildMatScript())
            local matGuid = spawned.getGUID()
            Wait.time(function()
                local m = getObjectFromGUID(matGuid)
                if not m then return end
                pcall(function() m.call("setupButtons") end)
                local count = 0
                local okB, btns = pcall(function() return m.getButtons() end)
                if okB and btns then count = #btns end
                broadcastToColor("Player mat ready: " .. count ..
                    " of 12 starter-slot buttons live.", player.color,
                    { 0.75, 0.95, 0.75 })
            end, 2.5)
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
    MatSlotDice[object.getGUID()] = nil
end

-- =====================================================================
-- STARTING DICE SLOTS - invisible click zones on the player mat
-- =====================================================================
-- Slot positions are fractions of the shipped board image
-- (u = across from the left, v = down from the top), MEASURED from
-- the final board PNG - if the board art is ever rebuilt with a
-- different layout, re-measure and update these numbers.
local STARTING_SLOTS = {
    { id = "combat_1", u = 0.23047, v = 0.71064, kind = "def",     pick = 1, label = "Combat - DEF" },
    { id = "combat_2", u = 0.25928, v = 0.71064, kind = "def",     pick = 2, label = "Combat - DEF" },
    { id = "combat_3", u = 0.28809, v = 0.71064, kind = "defplus", pick = 1, label = "Combat - DEF +1" },
    { id = "combat_4", u = 0.31689, v = 0.71064, kind = "atk",     pick = 1, label = "Combat - ATK" },
    { id = "combat_5", u = 0.34521, v = 0.71064, kind = "daze",    pick = 1, label = "Combat - DAZE" },
    { id = "event_1",  u = 0.23047, v = 0.76226, kind = "event",   pick = 1, label = "Event - DEX" },
    { id = "event_2",  u = 0.25928, v = 0.76226, kind = "event",   pick = 1, label = "Event - DEX" },
    { id = "event_3",  u = 0.28809, v = 0.76226, kind = "event",   pick = 1, label = "Event - CON" },
    { id = "event_4",  u = 0.31665, v = 0.76226, kind = "event",   pick = 1, label = "Event - CON" },
    { id = "event_5",  u = 0.34521, v = 0.76226, kind = "event",   pick = 1, label = "Event - STR" },
    { id = "faction_1", u = 0.27051, v = 0.82306, kind = "faction", pick = 1, label = "Faction - Drunkard's Resilience" },
    { id = "faction_2", u = 0.30615, v = 0.82306, kind = "faction", pick = 1, label = "Faction - Hard Labor" },
}
local STARTING_SLOTS_BY_ID = {}
for _, def in ipairs(STARTING_SLOTS) do STARTING_SLOTS_BY_ID[def.id] = def end

-- The object script every spawned mat gets. It draws NO visible UI -
-- just invisible buttons over the printed slots - and forwards clicks
-- to Global.spawnStartingDie. Button positions are computed from the
-- tile's own bounds, so the zones sit on the printed slots whatever
-- scale the tile has. (%s placeholders: slot lines, click handlers.)
local MAT_SCRIPT_TEMPLATE = [==[
-- Korts Player Mat (object script, set by Global.lua at spawn time)
local SLOTS = {
%s
}
local SLOT_W_FRAC = 0.02222
local SLOT_H_FRAC = 0.02610
-- DEBUG: zones drawn as visible red squares, raised well above the
-- mat and oversized, so their true position can be seen and reported.
-- Flip to false for the invisible production version once the
-- placement is confirmed in TTS.
local DEBUG_ZONES = true

function setupButtons()
    self.clearButtons()
    local bounds = self.getBoundsNormalized()
    local scale = self.getScale()
    local nx = bounds.size.x / scale.x
    local nz = bounds.size.z / scale.z
    local topY = (bounds.size.y / scale.y) / 2
    for _, slot in ipairs(SLOTS) do
        self.createButton({
            click_function = "slot_" .. slot.id,
            label = "",
            tooltip = slot.tip,
            position = { (slot.u - 0.5) * nx,
                         topY + (DEBUG_ZONES and 1.2 or 0.35),
                         (slot.v - 0.5) * nz },
            rotation = { 0, 0, 0 },
            width = SLOT_W_FRAC * nx * (DEBUG_ZONES and 2.2 or 1.2),
            height = SLOT_H_FRAC * nz * (DEBUG_ZONES and 2.2 or 1.2),
            color = DEBUG_ZONES and { 1, 0.25, 0.25, 0.55 }
                or { 0, 0, 0, 0 },
            hover_color = DEBUG_ZONES and { 1, 0.4, 0.4, 0.75 }
                or { 0, 0, 0, 0 },
            press_color = DEBUG_ZONES and { 0.9, 0.2, 0.2, 0.85 }
                or { 0, 0, 0, 0 },
            font_color = { 0, 0, 0, 0 },
        })
    end
end

function onLoad()
    -- Defer zone creation: doing it the instant this script lands
    -- races the tile's own image load - the bounds can still be the
    -- unloaded placeholder's, and a load reload can wipe buttons
    -- made too early. Global also calls setupButtons again as a
    -- backstop a couple of seconds after spawning.
    Wait.time(setupButtons, 1)
end

%s
]==]

buildMatScript = function()
    local slotLines, handlerLines = {}, {}
    for _, def in ipairs(STARTING_SLOTS) do
        slotLines[#slotLines + 1] = string.format(
            '    { id = "%s", u = %.5f, v = %.5f, tip = "Spawn die: %s" },',
            def.id, def.u, def.v, def.label)
        handlerLines[#handlerLines + 1] = string.format(
            'function slot_%s(_, player_color)\n' ..
            '    Global.call("spawnStartingDie", { mat = self.getGUID(), ' ..
            'slot = "%s", player = player_color })\nend', def.id, def.id)
    end
    return string.format(MAT_SCRIPT_TEMPLATE,
        table.concat(slotLines, "\n"), table.concat(handlerLines, "\n\n"))
end

-- Pick the catalog die that best matches a slot's kind.
local function pickCatalogDie(kind, pick)
    local scored = {}
    for _, entry in ipairs(DiceCatalog) do
        local faces = resolveFaces(entry)
        local counts = countPools(faces)
        local score
        if kind == "def" or kind == "defplus" then
            score = counts.defends
            if kind == "defplus" then
                for _, f in ipairs(faces) do
                    if f.id == "block_1" then score = score + 0.5 end
                end
            end
        elseif kind == "atk" then
            score = counts.attacks
        elseif kind == "daze" then
            score = counts.statuses
            for _, f in ipairs(faces) do
                if f.id == "status_daze" then score = score + 10 end
            end
        else  -- event / faction: not designed yet, any die as a stand-in
            score = math.random()
        end
        scored[#scored + 1] = { entry = entry, score = score }
    end
    table.sort(scored, function(a, b) return a.score > b.score end)
    return scored[math.min(pick or 1, #scored)].entry
end

-- Called from a mat's object script when a Starting Dice slot zone is
-- clicked: place that slot's die on the slot (replacing any die the
-- slot already holds). The die is PLACED, not rolled.
function spawnStartingDie(params)
    local mat = getObjectFromGUID(params.mat)
    local def = STARTING_SLOTS_BY_ID[params.slot]
    if not mat or not def then return end
    if FaceDatabase == nil or DiceCatalog == nil then
        broadcastToColor("The dice workshop is still warming up - try again in a second!",
            params.player, { 0.95, 0.55, 0.45 })
        return
    end

    local entry = pickCatalogDie(def.kind, def.pick)
    local faces = resolveFaces(entry)

    MatSlotDice[params.mat] = MatSlotDice[params.mat] or {}
    local oldGuid = MatSlotDice[params.mat][params.slot]
    if oldGuid then
        local old = getObjectFromGUID(oldGuid)
        if old then old.destruct() end
        MatSlotDice[params.mat][params.slot] = nil
    end

    -- The slot's world position, via the mat's own transform (so this
    -- still lands on the slot if the mat has been moved or rotated).
    local bounds = mat.getBoundsNormalized()
    local scale = mat.getScale()
    local localPos = {
        (def.u - 0.5) * (bounds.size.x / scale.x),
        (bounds.size.y / scale.y) / 2 + 1.2,
        (def.v - 0.5) * (bounds.size.z / scale.z),
    }
    local worldPos = mat.positionToWorld(localPos)

    local ownerName = playerDisplayName({ color = params.player })
    local dieName, note
    if def.kind == "event" or def.kind == "faction" then
        dieName = "Starting Die - " .. def.label .. " (stand-in)"
        note = "Stand-in die: the real " .. def.label ..
            " die is not designed yet. This slot's button is wired " ..
            "and will spawn it once it exists.\n\n"
    else
        dieName = "Starting Die - " .. def.label
        note = ""
    end

    local die = spawnObject({
        type = "Custom_Dice",
        position = worldPos,
        rotation = { 0, math.random(360), 0 },
        scale = { 1.4, 1.4, 1.4 },
        sound = true,
        callback_function = function(spawned)
            spawned.setName(dieName .. " - " .. ownerName)
            spawned.setDescription(note .. describeFaces(faces))
            spawned.setGMNotes(JSON.encode(faces))
            BuiltDice[spawned.getGUID()] = { faces = faces,
                owner = params.player, ownerName = ownerName }
            MatSlotDice[params.mat][params.slot] = spawned.getGUID()
        end,
    })
    if die then
        die.setCustomObject({
            image = GITHUB_RAW_BASE .. entry.texture,
            type = 1,  -- 1 = six-sided
        })
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
