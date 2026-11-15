--[[
    TrustSets - Trust party preset manager for Ashita v4 / Final Fantasy XI
    Version: 1.4.9 - v1.4.7 layout with Olympus-style gold corner ornaments

    Commands:
      /tsets or /trustsets       Toggle the GUI window
      /tset gui                 Legacy GUI command (still supported)
      /tset add NAME A, B, C    Create / update a preset
      /tset run NAME            Summon without dismissing existing Trusts
      /tset replace NAME        Dismiss all Trusts, then summon the preset
      /tset stop                Cancel pending summon commands
      /tset release             Dismiss all Trusts
      /tset list|show|delete|status|help

    Uses the normal FFXI /ma and /refa commands, not packets or recast bypasses.
    Each summon is checked against the Trust party roster and retried if absent.
--]]

addon.name    = 'trustsets';
addon.author  = 'Dugahst';
addon.version = '1.4.9';
addon.desc    = 'Trust party presets, verified summon retries, and an Olympus-style framed GUI.';

require 'common';
local settings = require 'settings';
local imgui = require 'imgui';

-- Allowed interval between sequential Trust casts. Defaults to 6 seconds.
local DEFAULT_SUMMON_INTERVAL_SECONDS = 6;
local SUMMON_INTERVAL_OPTIONS = { 4, 5, 6, 7 };
-- One original summon and up to two retries. The confirmation grace period
-- accounts for cast time and party-list latency on slower clients/servers.
local MAX_SUMMON_ATTEMPTS = 3;
local MIN_CONFIRM_SECONDS = 8;

-- Example sets; replace with Trusts learned on your character / server.
local default_settings = T{
    delay_seconds = DEFAULT_SUMMON_INTERVAL_SECONDS,
    ui_open = T{ false, },
    sets = T{
        leveling = T{ 'Valaineral', 'Kupipi', 'Shantotto II', 'Joachim', 'Koru-Moru' },
        magic    = T{ 'Amchuchu', 'Kupipi', 'Shantotto II', 'Koru-Moru', 'Ulmia' },
        starter  = T{ 'Valaineral', 'Kupipi', 'Naji' },
    },
};

local state = {
    config = settings.load(default_settings),
    queue = nil,
    ui = {
        -- Transient visibility; never restore the last open window on addon load.
        visible = T{ false, },
        selected = nil,
        name = { '' },
        capture_name = { '' },
        trusts = { { '' }, { '' }, { '' }, { '' }, { '' } },
        confirm_delete = nil,
        message = 'Select a preset or click New.',
    },
};

local function trim(s)
    return ((s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- ui_open in saved settings is a legacy field; GUI visibility is session-only.
local function normalize_settings()
    if (type(state.config.sets) ~= 'table') then
        state.config.sets = T{};
    end
    if (type(state.config.ui_open) ~= 'table') then
        state.config.ui_open = T{ false, };
    end
    if (type(state.config.ui_open[1]) ~= 'boolean') then
        state.config.ui_open[1] = false;
    end
    -- Previously v1.4.1 used a fixed interval; restore an optional saved
    -- delay, but only allow the four dropdown values.
    local delay = tonumber(state.config.delay_seconds);
    if (delay ~= 4 and delay ~= 5 and delay ~= 6 and delay ~= 7) then
        delay = DEFAULT_SUMMON_INTERVAL_SECONDS;
    end
    state.config.delay_seconds = delay;
end
normalize_settings();

local function say(message)
    state.ui.message = message;
    print(('[TrustSets] %s'):format(message));
end

local function save_settings()
    settings.save();
end

local function set_key(name)
    if (type(name) ~= 'string') then return nil; end
    local key = trim(name):lower();
    if (#key < 1 or #key > 24 or not key:match('^[%w_%-]+$')) then
        return nil;
    end
    return key;
end

local function validate_trust(name)
    -- Prevent command injection from user-editable Trust names.
    if (type(name) ~= 'string' or #name < 1 or #name > 64) then return false; end
    return name:match("^[%w%s%-%.'%(%)]+$") ~= nil;
end

-- The FFXI party member API returns many Trust names with the spaces
-- removed (for example, "MihliAliapoh" instead of the spell name
-- "Mihli Aliapoh"). Summon commands need the real spell name.
--
-- Resolve party-display names to summon-spell names, without guessing
-- alternative versions (II, UC) when the displayed name is ambiguous.
-- An explicit spell name the player entered, such as "Shantotto II",
-- is preserved and never reduced to the default version.
local function compact_trust_name(name)
    return (trim(name):lower():gsub('%s+', ''));
end

-- Built-in fallback for clients/servers with incomplete spell resources.
-- Includes multi-word Trusts and names where the party display omits (UC).
local canonical_trust_spells = {
    'D. Shantotto', 'Ferreous Coffin', 'Iron Eater', 'King of Hearts',
    'Kuyin Hathdenna', 'Lehko Habhoka', 'Lhe Lhangavo', 'Lhu Mhakaracca',
    'Mihli Aliapoh', 'Naja Salaheem', 'Naja Salaheem (UC)',
    'Nanaa Mihgo', 'Romaa Mihgo', 'Semih Lafihna', 'Shikaree Z',
    'Star Sibyl', 'Uka Totlihn', 'Invincible Shield (UC)',
    'Jakoh Wahcondalo (UC)', 'Apururu (UC)', 'Yoran-Oran (UC)',
    'Sylvie (UC)', 'Pieuje (UC)', 'Flaviria (UC)',
};
local canonical_by_compact = {};
for _, name in ipairs(canonical_trust_spells) do
    canonical_by_compact[compact_trust_name(name)] = name;
end

-- Add names from the client's actual spell resources when available.
-- The known Trust spell range is 896+, so this is a one-time small scan,
-- not something repeated every frame. No resource API is required for the
-- built-in fallback to work.
local function register_client_spell_names()
    if (not AshitaCore or not AshitaCore.GetResourceManager) then return; end
    local resources = AshitaCore:GetResourceManager();
    if (not resources or not resources.GetSpellById) then return; end
    for spell_id = 896, 1200 do
        local spell = resources:GetSpellById(spell_id);
        if (spell and spell.Name and type(spell.Name[1]) == 'string') then
            local name = trim(spell.Name[1]);
            if (name ~= '' and validate_trust(name)) then
                local compact = compact_trust_name(name);
                if (canonical_by_compact[compact] == nil) then
                    canonical_by_compact[compact] = name;
                end
            end
        end
    end
end
register_client_spell_names();

-- Party-only names for Unity Trusts omit their (UC) spell suffix.
-- Naja Salaheem is intentionally excluded because both versions exist.
local party_only_aliases = {
    ['apururu'] = 'Apururu (UC)',
    ['yoran-oran'] = 'Yoran-Oran (UC)',
    ['sylvie'] = 'Sylvie (UC)',
    ['flaviria'] = 'Flaviria (UC)',
    ['pieuje'] = 'Pieuje (UC)',
    ['invincibleshield'] = 'Invincible Shield (UC)',
    ['jakohwahcondalo'] = 'Jakoh Wahcondalo (UC)',
};

local function canonical_trust_name(name)
    local clean = trim(name);
    if (not validate_trust(clean)) then return clean; end
    local compact = compact_trust_name(clean);
    return party_only_aliases[compact] or canonical_by_compact[compact] or clean;
end

-- Repair v1.3 presets that were saved using the compact party names.
-- Only Trust name strings are changed; preset keys/order remain intact.
local function migrate_saved_trust_names()
    local updated = 0;
    for _, names in pairs(state.config.sets) do
        if (type(names) == 'table') then
            for index, stored in ipairs(names) do
                if (type(stored) == 'string') then
                    local corrected = canonical_trust_name(stored);
                    if (corrected ~= stored) then
                        names[index] = corrected;
                        updated = updated + 1;
                    end
                end
            end
        end
    end
    return updated;
end

if (migrate_saved_trust_names() > 0) then
    save_settings();
end

local function parse_trust_list(raw)
    if (not raw or raw == '') then
        return nil, 'Enter at least one Trust name.';
    end
    local result, seen = {}, {};
    for part in (raw .. ','):gmatch('(.-),') do
        local name = canonical_trust_name(part);
        if (not validate_trust(name)) then
            return nil, ('Invalid Trust name: "%s"'):format(name);
        end
        if (seen[name:lower()]) then
            return nil, ('Duplicate Trust: %s'):format(name);
        end
        seen[name:lower()] = true;
        result[#result + 1] = name;
        if (#result > 5) then
            return nil, 'A preset can contain at most five Trusts.';
        end
    end
    return result;
end

local function sorted_keys()
    local keys = {};
    for key in pairs(state.config.sets) do keys[#keys + 1] = key; end
    table.sort(keys);
    return keys;
end

local function fill_editor(key)
    state.ui.selected = key;
    state.ui.confirm_delete = nil;
    state.ui.name[1] = key or '';
    local names = key and state.config.sets[key] or nil;
    for i = 1, 5 do
        state.ui.trusts[i][1] = (names and names[i]) or '';
    end
end

-- Read the LOCAL party (slots 1-5; slot 0 is the player).  Trusts can be
-- identified by the entity's Trust-owner target index.  Some server/client
-- combinations expose a Trust spawn flag (0x0E) instead; accept this only
-- for party members, never random nearby entities.  Do not save actual PCs.
local function get_active_trusts()
    local memory = AshitaCore:GetMemoryManager();
    if (memory == nil) then return nil, 'FFXI party memory is unavailable.'; end
    local party = memory:GetParty();
    local entity = memory:GetEntity();
    if (party == nil or entity == nil) then
        return nil, 'Party/entity information is unavailable.';
    end

    local player_index = party:GetMemberTargetIndex(0);
    local names, seen, ambiguous = {}, {}, {};
    local ambiguous_names = {
        ['arciela'] = true, ['ingrid'] = true, ['iroha'] = true,
        ['lilisette'] = true, ['lion'] = true, ['mumor'] = true,
        ['nashmeira'] = true, ['prishe'] = true, ['shantotto'] = true,
        ['tenzen'] = true, ['zeid'] = true,
        ['aldo'] = true, ['ayame'] = true, ['maat'] = true,
        ['najasalaheem'] = true, ['excenmille'] = true,
    };
    for i = 1, 5 do
        local active = party:GetMemberIsActive(i);
        if (active == 1 or active == true) then
            local id = party:GetMemberServerId(i);
            local index = party:GetMemberTargetIndex(i);
            local display_name = trim(party:GetMemberName(i));
            if (type(id) == 'number' and id ~= 0 and
                type(index) == 'number' and index > 0 and
                validate_trust(display_name)) then
                local owner = entity:GetTrustOwnerTargetIndex(index);
                local flags = entity:GetSpawnFlags(index);
                local is_trust = (type(player_index) == 'number' and player_index > 0 and
                    type(owner) == 'number' and owner == player_index);
                -- 0x0E is the client entity type normally used for Trusts.
                if (not is_trust and flags == 0x0E) then is_trust = true; end
                if (is_trust) then
                    local lower = compact_trust_name(display_name);
                    local name = canonical_trust_name(display_name);
                    if (not seen[name:lower()]) then
                        seen[name:lower()] = true;
                        names[#names + 1] = name;
                        if (ambiguous_names[lower]) then
                            ambiguous[#ambiguous + 1] = display_name;
                        end
                    end
                end
            end
        end
    end
    if (#names == 0) then
        return nil, 'No active Trusts detected. Summon Trusts and try again.';
    end
    return names, nil, ambiguous;
end

-- Read currently active Trust party members for summon verification.
-- Retain server ids to distinguish a NEW summon from a pre-existing Trust.
-- This uses the same Trust-owner / 0x0E checks as party capture and never
-- treats real players as successfully summoned Trusts.
local function read_trust_party_members()
    local ok, members = pcall(function ()
        local memory = AshitaCore:GetMemoryManager();
        if (memory == nil) then error('memory manager unavailable'); end
        local party, entity = memory:GetParty(), memory:GetEntity();
        if (party == nil or entity == nil) then error('party/entity memory unavailable'); end
        local player_index = party:GetMemberTargetIndex(0);
        local result = {};
        for i = 1, 5 do
            local active = party:GetMemberIsActive(i);
            if (active == 1 or active == true) then
                local id = party:GetMemberServerId(i);
                local index = party:GetMemberTargetIndex(i);
                local name = trim(party:GetMemberName(i));
                if (type(id) == 'number' and id ~= 0 and
                    type(index) == 'number' and index > 0 and
                    validate_trust(name)) then
                    local owner = entity:GetTrustOwnerTargetIndex(index);
                    local flags = entity:GetSpawnFlags(index);
                    local is_trust = (type(player_index) == 'number' and player_index > 0 and
                        type(owner) == 'number' and owner == player_index);
                    if (not is_trust and flags == 0x0E) then is_trust = true; end
                    if (is_trust) then
                        result[#result + 1] = { id = id, name = name };
                    end
                end
            end
        end
        return result;
    end);
    if (not ok) then
        return nil, 'Cannot read the active Trust party; queue stopped to avoid duplicate casts.';
    end
    return members;
end

-- FFXI sometimes reports the summoned NPC without the spell's II / (UC)
-- suffix, and sometimes without spaces. Match by a display-safe key.
-- Variant names can therefore be ambiguous, as with party capture.
local function trust_party_key(name)
    local key = trim(name):lower();
    key = key:gsub('%s*%(%s*uc%s*%)$', ''):gsub('%s+ii$', '');
    return compact_trust_name(key);
end

local function matching_trust_member(members, name, prior_ids)
    local wanted = trust_party_key(name);
    for _, member in ipairs(members) do
        if (trust_party_key(member.name) == wanted and
            (prior_ids == nil or not prior_ids[member.id])) then
            return member;
        end
    end
    return nil;
end

local function member_id_set(members)
    local ids = {};
    for _, member in ipairs(members) do ids[member.id] = true; end
    return ids;
end

local function unique_captured_key()
    for i = 1, 9999 do
        local key = ('party_%d'):format(i);
        if (state.config.sets[key] == nil) then return key; end
    end
    return nil;
end

-- Capture is always a NEW preset. Never silently overwrite an existing one.
local function save_preset(key, names)
    local was_existing = state.config.sets[key] ~= nil;
    local corrected = {};
    for i, name in ipairs(names) do
        corrected[i] = canonical_trust_name(name);
    end
    state.config.sets[key] = T(corrected);
    save_settings();
    fill_editor(key);
    say(('%s preset "%s" (%d Trusts).'):format(
        was_existing and 'Updated' or 'Saved', key, #names));
end

local function save_current_trusts()
    local names, err, ambiguous = get_active_trusts();
    if (not names) then say(err); return; end
    local desired_name = trim(state.ui.capture_name[1]);
    local key;
    if (desired_name == '') then
        key = unique_captured_key();
    else
        key = set_key(desired_name);
        if (not key) then
            say('New set name must be 1-24 letters, numbers, _ or -.');
            return;
        end
        if (state.config.sets[key] ~= nil) then
            say(('Preset "%s" already exists. Enter a new set name.'):format(key));
            return;
        end
    end
    if (key == nil) then say('Too many captured presets. Delete an old set.'); return; end
    save_preset(key, names);
    state.ui.capture_name[1] = '';
    if (#ambiguous > 0) then
        say(('Check the captured names in the editor: %s may have II or other variants. The party list does not show the version.'):format(table.concat(ambiguous, ', ')));
    end
end

local function save_editor()
    local key = set_key(state.ui.name[1]);
    if (not key) then
        say('Preset name must be 1-24 letters, numbers, _ or - (no spaces).');
        return;
    end
    local names = {};
    for i = 1, 5 do
        local name = canonical_trust_name(state.ui.trusts[i][1]);
        if (name ~= '') then names[#names + 1] = name; end
    end
    local validated, err = parse_trust_list(table.concat(names, ','));
    if (not validated) then say(err); return; end
    save_preset(key, validated);
end

local function add_set(args)
    local name, raw = args:match('^(%S+)%s+(.+)$');
    local key = set_key(name);
    if (not key) then
        say('Usage: /tset add NAME Trust One, Trust Two (NAME has no spaces).');
        return;
    end
    local names, err = parse_trust_list(raw);
    if (not names) then say(err); return; end
    save_preset(key, names);
end

local function remove_set(raw)
    local key = set_key(raw);
    if (not key or not state.config.sets[key]) then
        say('Unknown preset. Use /tset list.');
        return;
    end
    state.config.sets[key] = nil;
    save_settings();
    if (state.ui.selected == key) then fill_editor(nil); end
    say(('Deleted preset "%s".'):format(key));
end

local function list_sets()
    local keys = sorted_keys();
    if (#keys == 0) then
        say('No presets saved. Type /tsets to open the GUI.');
        return;
    end
    say('Saved Trust presets:');
    for _, key in ipairs(keys) do
        local names = state.config.sets[key];
        say(('  %s (%d): %s'):format(key, #names, table.concat(names, ', ')));
    end
end

local function show_set(raw)
    local key = set_key(raw);
    if (not key or not state.config.sets[key]) then
        say('Unknown preset. Use /tset list.');
        return;
    end
    say(('%s: %s'):format(key, table.concat(state.config.sets[key], ', ')));
end

local function send_chat_command(command)
    AshitaCore:GetChatManager():QueueCommand(1, command);
end

local function stop_queue(silent)
    if (state.queue ~= nil) then
        state.queue = nil;
        if (not silent) then say('Pending Trust commands canceled.'); end
    elseif (not silent) then
        say('No summoning sequence is active.');
    end
end

local function finish_queue(queue)
    if (state.queue ~= queue) then return; end
    state.queue = nil;
    local failures = #queue.failures;
    local summary = ('Finished "%s": %d summoned, %d already present, %d failed.'):format(
        queue.name, queue.verified, queue.existing, failures);
    if (failures > 0) then
        summary = summary .. ' Not verified: ' .. table.concat(queue.failures, ', ') .. '.';
    end
    say(summary);
end

-- Advance only after seeing the Trust join the party, discovering that it
-- was already present, or exhausting all attempts for this Trust.
local function advance_queue(queue)
    queue.index = queue.index + 1;
    queue.attempts = 0;
    queue.phase = 'ready';
    queue.prior_ids = nil;
    if (queue.index > #queue.names) then
        finish_queue(queue);
    else
        -- Keep the user's 4-7 second minimum between sent casts. Checking
        -- can take longer, but never shortens the selected cast delay.
        queue.next_at = math.max(os.time(),
            (queue.last_sent_at or os.time()) + state.config.delay_seconds);
    end
end

local function start_set(raw, replace)
    local key = set_key(raw);
    if (not key or not state.config.sets[key]) then
        say('Unknown preset. Use /tset list.');
        return;
    end
    local names = state.config.sets[key];
    if (#names == 0) then say('That preset is empty.'); return; end

    -- Do not start a verification queue when party memory is inaccessible.
    local members, err = read_trust_party_members();
    if (not members) then say(err); return; end

    local copy = {};
    for i, name in ipairs(names) do copy[i] = canonical_trust_name(name); end
    state.queue = {
        name = key,
        names = copy,
        index = 1,
        attempts = 0,
        phase = 'ready',
        next_at = os.time() + (replace and 4 or 0),
        last_sent_at = nil,
        prior_ids = nil,
        verified = 0,
        existing = 0,
        failures = {},
        replace = replace,
    };
    if (replace) then
        -- Only the explicit Replace action dismisses current Trusts.
        send_chat_command('/refa all');
        say(('Dismissed current Trusts; starting "%s" after 4 seconds.'):format(key));
    else
        say(('Summoning "%s" (%d Trusts; automatic retries enabled).'):format(key, #copy));
    end
end

local function process_summon_queue()
    local queue = state.queue;
    if (queue == nil) then return; end
    local now = os.time();
    if (queue.phase == 'ready' and now < queue.next_at) then return; end

    local members, err = read_trust_party_members();
    if (not members) then
        stop_queue(true);
        say(err);
        return;
    end
    local name = queue.names[queue.index];
    if (not name) then finish_queue(queue); return; end

    if (queue.phase == 'waiting') then
        if (matching_trust_member(members, name, queue.prior_ids)) then
            queue.verified = queue.verified + 1;
            say(('Confirmed %d/%d: %s (attempt %d).'):format(
                queue.index, #queue.names, name, queue.attempts));
            advance_queue(queue);
            return;
        end
        if (now < queue.verify_by) then return; end
        if (queue.attempts >= MAX_SUMMON_ATTEMPTS) then
            queue.failures[#queue.failures + 1] = name;
            say(('Could not verify %s after %d attempts; moving to next Trust.'):format(
                name, MAX_SUMMON_ATTEMPTS));
            advance_queue(queue);
            return;
        end
        -- Verification timed out. Recheck the party immediately before
        -- retrying to avoid sending an unnecessary duplicate command.
        queue.phase = 'ready';
        queue.next_at = now;
    end

    -- Skip Trusts already summoned before this set began, instead of
    -- repeatedly attempting to cast an existing party member.
    if (queue.attempts == 0 and matching_trust_member(members, name)) then
        queue.existing = queue.existing + 1;
        say(('Already summoned %d/%d: %s.'):format(queue.index, #queue.names, name));
        advance_queue(queue);
        return;
    end

    -- For each attempt remember the roster immediately before the cast.
    -- Only a matching NEW Trust counts as a successful summons.
    queue.prior_ids = member_id_set(members);
    queue.attempts = queue.attempts + 1;
    queue.phase = 'waiting';
    queue.last_sent_at = now;
    queue.verify_by = now + math.max(MIN_CONFIRM_SECONDS, state.config.delay_seconds + 3);
    send_chat_command(('/ma "%s" <me>'):format(name));
    say(('Summoning %d/%d: %s (attempt %d/%d).'):format(
        queue.index, #queue.names, name, queue.attempts, MAX_SUMMON_ATTEMPTS));
end

local function release_all()
    stop_queue(true);
    send_chat_command('/refa all');
    say('Sent /refa all (dismiss all current Trusts).');
end

local function set_ui_visible(visible)
    state.ui.visible[1] = visible;
end

local function print_help()
    say('Commands:');
    say('  /tsets or /trustsets             - Toggle graphical preset manager');
    say('  /tset list                      - List presets');
    say('  /tset capture [NAME]            - Save your current Trust party');
    say('  /tset show NAME                 - Show one preset');
    say('  /tset add NAME A, B, C          - Save/update preset (up to 5 Trusts)');
    say('  /tset run NAME                  - Summon without dismissing existing');
    say('  /tset replace NAME              - Dismiss all, then summon preset');
    say('  /tset stop                      - Stop remaining summon commands');
    say('  /tset status                    - Show queue progress');
    say('  /tset delay [4|5|6|7]           - View/set seconds between summons');
    say('  /tset release                   - Dismiss all Trusts');
    say('  /tset delete NAME               - Delete preset');
end

-- The settings library saves separately for each FFXI character.
settings.register('settings', 'trustsets_settings_update', function (updated)
    stop_queue(true);
    if (updated ~= nil) then state.config = updated; end
    normalize_settings();
    migrate_saved_trust_names();
    fill_editor(nil);
    save_settings();
end);

ashita.events.register('load', 'trustsets_load', function ()
    say('Loaded. GUI: /tsets or /trustsets   |   Commands: /tset help');
end);

ashita.events.register('unload', 'trustsets_unload', function ()
    stop_queue(true);
    save_settings();
end);

ashita.events.register('command', 'trustsets_command', function (e)
    local verb, rest = e.command:match('^%s*/([%w]+)%s*(.-)%s*$');
    if (verb == nil or (verb:lower() ~= 'tset' and verb:lower() ~= 'tsets' and verb:lower() ~= 'trustsets')) then
        return;
    end
    e.blocked = true;
    local cmd, args = rest:match('^(%S+)%s*(.-)%s*$');
    cmd = cmd and cmd:lower() or 'gui';
    args = args or '';

    if (cmd == 'gui' or cmd == 'ui' or cmd == 'panel') then
        set_ui_visible(not state.ui.visible[1]);
    elseif (cmd == 'open') then
        set_ui_visible(true);
    elseif (cmd == 'close') then
        set_ui_visible(false);
    elseif (cmd == 'help') then
        print_help();
    elseif (cmd == 'capture' or cmd == 'current') then
        state.ui.capture_name[1] = args;
        save_current_trusts();
    elseif (cmd == 'list') then
        list_sets();
    elseif (cmd == 'show') then
        show_set(args);
    elseif (cmd == 'add' or cmd == 'save') then
        add_set(args);
    elseif (cmd == 'delete' or cmd == 'remove') then
        remove_set(args);
    elseif (cmd == 'run' or cmd == 'summon') then
        start_set(args, false);
    elseif (cmd == 'replace' or cmd == 'switch') then
        start_set(args, true);
    elseif (cmd == 'stop' or cmd == 'cancel') then
        stop_queue(false);
    elseif (cmd == 'release') then
        release_all();
    elseif (cmd == 'status') then
        if (state.queue) then
            say(('Summoning "%s": Trust %d/%d (%s; attempt %d/%d), %d verified, %d failed.'):format(
                state.queue.name, state.queue.index, #state.queue.names,
                state.queue.names[state.queue.index] or 'none',
                state.queue.attempts, MAX_SUMMON_ATTEMPTS,
                state.queue.verified, #state.queue.failures));
        else
            say('Idle. No pending Trust commands.');
        end
    elseif (cmd == 'delay') then
        if (args == '') then
            say(('Summon delay is %d seconds. Use /tset delay 4, 5, 6 or 7.'):format(state.config.delay_seconds));
        else
            local delay = tonumber(args);
            if (delay ~= 4 and delay ~= 5 and delay ~= 6 and delay ~= 7) then
                say('Valid summon delays: 4, 5, 6 or 7 seconds.');
                return;
            end
            state.config.delay_seconds = delay;
            save_settings();
            say(('Summon delay set to %d seconds.'):format(delay));
        end
    else
        say('Unknown command. Type /tset help.');
    end
end);

-- The Olympus Wiki-inspired palette is scoped to this window only; it does
-- NOT overwrite the style of other Ashita addons. Colors are normalized RGBA.
-- Deep, almost-black midnight blue with muted blue-gray body text, gold trim,
-- and icy-blue highlights, matching the provided reference screenshot.
local ui_colors = {
    { ImGuiCol_WindowBg,         { 0.027, 0.043, 0.098, 0.985 } }, -- #070B19
    { ImGuiCol_ChildBg,          { 0.031, 0.051, 0.106, 0.990 } }, -- #080D1B
    { ImGuiCol_TitleBg,          { 0.051, 0.086, 0.196, 1.000 } }, -- #0D1632
    { ImGuiCol_TitleBgActive,    { 0.051, 0.086, 0.196, 1.000 } },
    { ImGuiCol_Border,           { 0.56,  0.44,  0.17,  0.95  } }, -- old gold
    { ImGuiCol_Separator,        { 0.53,  0.42,  0.17,  0.85  } },
    { ImGuiCol_Text,             { 0.89,  0.92,  0.98,  1.00  } },
    { ImGuiCol_TextDisabled,     { 0.53,  0.59,  0.70,  1.00  } },
    { ImGuiCol_FrameBg,          { 0.057, 0.098, 0.215, 1.00  } },
    { ImGuiCol_FrameBgHovered,   { 0.080, 0.137, 0.267, 1.00  } },
    { ImGuiCol_FrameBgActive,    { 0.105, 0.175, 0.317, 1.00  } },
    { ImGuiCol_Button,           { 0.067, 0.118, 0.247, 1.00  } },
    { ImGuiCol_ButtonHovered,    { 0.113, 0.174, 0.320, 1.00  } },
    { ImGuiCol_ButtonActive,     { 0.145, 0.208, 0.348, 1.00  } },
    { ImGuiCol_Header,           { 0.153, 0.214, 0.325, 0.95  } },
    { ImGuiCol_HeaderHovered,    { 0.193, 0.259, 0.389, 1.00  } },
    { ImGuiCol_HeaderActive,     { 0.231, 0.293, 0.406, 1.00  } },
    { ImGuiCol_ScrollbarBg,      { 0.030, 0.046, 0.089, 1.00  } },
    { ImGuiCol_ScrollbarGrab,    { 0.39,  0.34,  0.17,  1.00  } },
};
local ui_accent = { 0.97, 0.84, 0.39, 1.00 }; -- glowing gold headings
local ui_muted  = { 0.66, 0.73, 0.83, 1.00 }; -- pale steel blue text
local ui_link   = { 0.52, 0.79, 1.00, 1.00 }; -- luminous blue highlights
local ui_warn   = { 0.94, 0.65, 0.46, 1.00 };

local function push_gui_theme()
    for _, entry in ipairs(ui_colors) do
        imgui.PushStyleColor(entry[1], entry[2]);
    end
    -- The wiki's panels and controls are crisp, with thin gold outlines.
    -- Stay with ImGuiStyleVars present in the original addon/Ashita v4.
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 3);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 1);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 1);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 13, 11 });
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8, 5 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 7, 5 });
    -- Gold outlines for the input fields and combo, not just the children.
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
end

local function pop_gui_theme()
    imgui.PopStyleVar(7);
    imgui.PopStyleColor(#ui_colors);
end

-- Keep text slightly smaller without modifying Ashita's global ImGui font.
-- Modern ImGui accepts a font and size in PushFont; earlier Ashita v4
-- versions instead have a per-window SetWindowFontScale method.
local function push_compact_font()
    if ((tonumber(IMGUI_VERSION_NUM) or 0) >= 19200) then
        -- Some Ashita installations use older GUI bindings; avoid
        -- crashing the addon if their PushFont signature differs.
        local ok = pcall(function ()
            imgui.PushFont(imgui.GetFont(), imgui.GetFontSize() * 0.94);
        end);
        return ok;
    end
    return false;
end

local function scale_legacy_window_font()
    if ((tonumber(IMGUI_VERSION_NUM) or 0) < 19200 and type(imgui.SetWindowFontScale) == 'function') then
        pcall(imgui.SetWindowFontScale, 0.94);
    end
end

-- Buttons follow the Wiki's flat midnight-blue / antique-gold treatment.
local function accent_button(label, size)
    imgui.PushStyleColor(ImGuiCol_Text,          { 0.98, 0.87, 0.52, 1.00 });
    imgui.PushStyleColor(ImGuiCol_Button,        { 0.077, 0.132, 0.254, 1.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.166, 0.208, 0.298, 1.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.223, 0.252, 0.306, 1.00 });
    local clicked = imgui.Button(label, size);
    imgui.PopStyleColor(4);
    return clicked;
end

-- Dangerous actions are darker/warmer but stay within the navy/gold palette.
local function danger_button(label, size)
    imgui.PushStyleColor(ImGuiCol_Button,        { 0.205, 0.122, 0.160, 1.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.299, 0.162, 0.188, 1.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.348, 0.181, 0.197, 1.00 });
    local clicked = imgui.Button(label, size);
    imgui.PopStyleColor(3);
    return clicked;
end

local function full_width_input(id, buffer, max_length)
    imgui.PushItemWidth(-1);
    imgui.InputText(id, buffer, max_length);
    imgui.PopItemWidth();
end

local function render_preset_sidebar(pane_height)
    imgui.TextColored(ui_accent, 'LIBRARY');
    local keys = sorted_keys();
    imgui.TextColored(ui_muted, ('%d SAVED GROUPS'):format(#keys));
    if (imgui.Button('+ New preset', { -1, 32 })) then
        fill_editor(nil);
        state.ui.message = 'New preset: enter a name and up to five Trusts.';
    end
    imgui.Separator();

    -- Preserve enough room for the Capture controls below. The list
    -- itself scrolls only once there are more groups than will fit.
    local list_height = math.max(92, math.min(190, pane_height - 325));
    imgui.BeginChild('##trustsets_list', { 0, list_height }, 0);
    if (#keys == 0) then
        imgui.TextColored(ui_muted, 'No saved parties yet.');
    end
    for _, key in ipairs(keys) do
        local names = state.config.sets[key];
        local label = ('  %s    %d/5##preset_%s'):format(key, #names, key);
        if (imgui.Selectable(label, state.ui.selected == key)) then
            fill_editor(key);
        end
    end
    imgui.EndChild();

    imgui.Separator();
    imgui.TextColored(ui_accent, 'CAPTURE YOUR PARTY');
    imgui.TextColored(ui_muted, 'New preset name (optional)');
    full_width_input('##capture_name', state.ui.capture_name, 25);
    if (accent_button('Save Current Trusts', { -1, 34 })) then
        save_current_trusts();
    end
    imgui.TextWrapped('Leave name blank to auto-name. Check alternate Trust versions after capture.');
end

local function render_editor()
    imgui.TextColored(ui_accent, 'PRESET EDITOR');
    if (state.ui.selected ~= nil) then
        imgui.TextColored(ui_link, ('EDITING  /  %s'):format(state.ui.selected));
    else
        imgui.TextColored(ui_link, 'NEW GROUP  /  UNSAVED');
    end

    imgui.TextColored(ui_muted, 'Preset name');
    full_width_input('##preset_name', state.ui.name, 25);
    imgui.Spacing();
    imgui.TextColored(ui_muted, 'TRUST MEMBERS  /  SUMMON ORDER');
    for i = 1, 5 do
        imgui.TextColored(ui_muted, ('%02d'):format(i));
        imgui.SameLine();
        imgui.PushItemWidth(-1);
        imgui.InputText(('##trust_%d'):format(i), state.ui.trusts[i], 65);
        imgui.PopItemWidth();
    end
    if (accent_button('Save preset', { 151, 32 })) then
        save_editor();
    end
    imgui.SameLine();
    if (state.ui.confirm_delete ~= nil) then
        if (danger_button('Confirm delete', { 144, 32 })) then
            remove_set(state.ui.confirm_delete);
            state.ui.confirm_delete = nil;
        end
        imgui.SameLine();
        if (imgui.Button('Cancel', { 68, 32 })) then
            state.ui.confirm_delete = nil;
        end
    elseif (danger_button('Delete selected', { 150, 32 })) then
        if (state.ui.selected ~= nil) then
            state.ui.confirm_delete = state.ui.selected;
            state.ui.message = 'Confirm delete to remove the selected preset.';
        else
            state.ui.message = 'Select a saved preset before deleting.';
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored(ui_accent, 'PARTY CONTROLS');
    if (accent_button('Summon selected', { 153, 34 })) then
        start_set(state.ui.selected, false);
    end
    imgui.SameLine();
    if (danger_button('Replace ALL', { 146, 34 })) then
        start_set(state.ui.selected, true);
    end
    imgui.TextColored(ui_muted, 'Replace ALL first dismisses your current Trusts.');
end

local function render_queue_footer()
    imgui.Separator();
    local queue = state.queue;
    if (queue ~= nil) then
        local checked = queue.index - 1;
        imgui.TextColored(ui_accent, ('SUMMONING  %s'):format(queue.name));
        imgui.SameLine();
        imgui.TextColored(ui_muted, ('%d / %d checked  |  Attempt %d/%d'):format(
            checked, #queue.names, queue.attempts, MAX_SUMMON_ATTEMPTS));
        imgui.ProgressBar(checked / #queue.names, { -1, 9 }, '');
    else
        imgui.TextColored(ui_accent, 'READY');
        imgui.SameLine();
        imgui.TextColored(ui_muted, 'No active summon queue');
    end
    if (imgui.Button('Stop queue', { 125, 30 })) then
        stop_queue(false);
    end
    imgui.SameLine();
    if (danger_button('Dismiss all Trusts', { 172, 30 })) then
        release_all();
    end
    -- Place the delay selector in the always-visible footer next to the
    -- queue controls; never bury it inside the editor's scroll area.
    imgui.SameLine();
    imgui.TextColored(ui_muted, 'Cast delay');
    imgui.SameLine();
    imgui.PushItemWidth(117);
    if (imgui.BeginCombo('##trustsets_cast_delay', ('%d sec'):format(state.config.delay_seconds))) then
        for _, delay in ipairs(SUMMON_INTERVAL_OPTIONS) do
            if (imgui.Selectable(('%d seconds'):format(delay), state.config.delay_seconds == delay)) then
                state.config.delay_seconds = delay;
                save_settings();
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.Spacing();
    imgui.TextWrapped(state.ui.message or '');
    imgui.Separator();
    imgui.TextColored(ui_link, 'GUI  /tsets   or   /trustsets      -      TrustSets v1.4.9 by Dugahst');
end

-- Gold corner pieces based on the Olympus Hate window-corner reference.
-- These are DRAWING ONLY and do not change any mouse / input handling.
-- The reference draws each L just outside the window. Extending the draw
-- list's clip rect is required, otherwise ImGui clips away the gold bracket.
local corner_gold = { 0.910, 0.741, 0.235, 1.00 };
local corner_highlight = { 1.000, 0.906, 0.627, 1.00 };

local function draw_window_corners()
    -- Ashita's Olympus theme uses two numeric returns here. Do not read
    -- `.x`/`.y` from Sugarmath vectors: that caused the old GUI crash.
    local ok, x0, y0, w, h, dl = pcall(function ()
        local x, y = imgui.GetWindowPos();
        local width, height = imgui.GetWindowSize();
        return x, y, width, height, imgui.GetWindowDrawList();
    end);
    if (not ok or type(x0) ~= 'number' or type(y0) ~= 'number' or
        type(w) ~= 'number' or type(h) ~= 'number' or w <= 0 or h <= 0 or
        dl == nil) then
        return;
    end

    local was_clipped = false;
    -- Drawing is optional and guarded: if a particular Ashita build lacks
    -- a draw-list call, the preset editor and summon logic still work.
    pcall(function ()
        local function packed(c, a)
            return imgui.GetColorU32({ c[1], c[2], c[3], a });
        end
        local glow = packed(corner_gold, 0.22);
        local gold = packed(corner_gold, 1.00);
        local gem  = packed(corner_highlight, 1.00);
        local arm, offset, inset = 16, 3, 3.5;
        dl:PushClipRectFullScreen();
        was_clipped = true;

        -- Both right-angle strokes head INWARD from a point three pixels
        -- OUTSIDE the corresponding window corner. The inset gem is drawn
        -- just within the window, like the supplied close-up image.
        local function bracket(px, py, dx, dy)
            local bx = px - dx * offset;
            local by = py - dy * offset;
            local to_h = { bx + dx * arm, by };
            local to_v = { bx, by + dy * arm };
            dl:AddLine({ bx, by }, to_h, glow, 5);
            dl:AddLine({ bx, by }, to_v, glow, 5);
            dl:AddLine({ bx - dx, by }, to_h, gold, 2);
            dl:AddLine({ bx, by - dy }, to_v, gold, 2);
            local cx, cy = px + dx * inset, py + dy * inset;
            dl:AddQuadFilled(
                { cx, cy - inset }, { cx + inset, cy },
                { cx, cy + inset }, { cx - inset, cy }, gem);
        end

        bracket(x0, y0, 1, 1);
        bracket(x0 + w, y0, -1, 1);
        bracket(x0, y0 + h, 1, -1);
        bracket(x0 + w, y0 + h, -1, -1);
    end);
    -- Clean up even if a draw method throws; never corrupt the clip stack.
    if (was_clipped) then
        pcall(function () dl:PopClipRect(); end);
    end
end

local function render_gui()
    if (not state.ui.visible[1]) then return; end

    imgui.SetNextWindowSize({ 700, 730 }, ImGuiCond_FirstUseEver);
    push_gui_theme();
    if (imgui.Begin('TrustSets  |  Trust Party Manager##trustsets_main', state.ui.visible)) then
        draw_window_corners();
        local pushed_font = push_compact_font();
        if (not pushed_font) then scale_legacy_window_font(); end
        imgui.TextColored(ui_accent, 'TRUSTSETS');
        imgui.SameLine();
        imgui.TextColored(ui_link, '  /  TRUST PARTY MANAGER');
        imgui.TextColored(ui_muted, 'Save groups, capture your active party, and summon with one click.');
        imgui.Separator();
        imgui.Spacing();

        -- Give both panes more room as the main window is made taller.
        -- ImGui's default behavior shows scrollbars ONLY if content overflows;
        -- do not set AlwaysVerticalScrollbar or NoScrollbar on these panes.
        local pane_height = math.max(360, math.floor(imgui.GetWindowHeight() - 240));
        imgui.BeginChild('##trustsets_sidebar', { 240, pane_height }, ImGuiChildFlags_Borders);
        if (not pushed_font) then scale_legacy_window_font(); end
        render_preset_sidebar(pane_height);
        imgui.EndChild();
        imgui.SameLine();
        imgui.BeginChild('##trustsets_editor', { 0, pane_height }, ImGuiChildFlags_Borders);
        if (not pushed_font) then scale_legacy_window_font(); end
        render_editor();
        imgui.EndChild();
        render_queue_footer();
        if (pushed_font) then imgui.PopFont(); end
    end
    imgui.End();
    pop_gui_theme();
end

-- Runs once each frame. Summoning is only performed for the user-selected
-- preset. No action-packet injection or automatic background summoning.
ashita.events.register('d3d_present', 'trustsets_present', function ()
    process_summon_queue();
    render_gui();
end);
