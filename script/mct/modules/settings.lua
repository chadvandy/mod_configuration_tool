--- Settings Object. INTERNAL USE ONLY.
-- @classmod mct_settings

local mct = mct

local settings = {
    settings_file = "mct_settings.lua",
    tab = 0,

    new_settings = {},
}

local tab = 0

function settings:save_mct_settings()
    local file = io.open(self.settings_file, "w+")

    self.tab = 0

    local str = "return {\n"

    local mods = mct:get_mods()
    for mod_key, mod_obj in pairs(mods) do
        local addendum = mod_obj:save_mct_settings()

        str = str .. addendum
    end

    --mct:log("starting run through table")
    --str = run_through_table(data, str)
    --mct:log("ending run through table")

    str = str .. "}"

    self.tab = 0

    file:write(str)
    file:close()
end

function settings:local_only_finalize(sent_by_host)
    -- it's the client; only finalize local-only stuff
    mct:log("Finalizing settings mid-campaign for MP, local-only.")
    local all_mods = mct:get_mods()

    for mod_key, mod_obj in pairs(all_mods) do
        local fin = mod_obj:get_settings()

        mct:log("Looping through mct_mod ["..mod_key.."]")
        local all_options = mod_obj:get_options()

        for option_key, option_obj in pairs(all_options) do
            if option_obj:get_local_only() then
                mct:log("Editing mct_option ["..option_key.."]")

                -- only trigger the option-changed event if it's actually changing setting
                local selected = option_obj:get_selected_setting()
                if option_obj:get_finalized_setting() ~= selected then
                    option_obj:set_finalized_setting(selected)
                    fin[option_key] = selected
                end
            end
        end

        mod_obj._finalized_settings = fin
    end

    mct._finalized = true
    
    mct.ui.locally_edited = false

    core:trigger_custom_event("MctFinalized", {["mct"] = mct, ["mp_sent"] = sent_by_host})
end

function settings:finalize(force)
    --mct:log("Finalizing Settings!")
    --local ret = {}
    local mods = mct:get_mods()

    -- don't save specific indices that will absolutely break shit or waste space if they're saved to Lua
    --[[local excluded_indices = {
        _FILEPATH = true,
        _uics = true,
        _mod = true,
        _template = true,
    }]]

    for key, mod in pairs(mods) do
        mct:log("Finalized mod ["..key.."]")
        mod:finalize_settings()

        --local data = {}

        --local options = mod:get_options()
        --for option_key, option_obj in pairs(options) do
            --data[option_key] = {}
            --data[option_key]._setting = option_obj:get_finalized_setting()
        --end

        --ret[key] = data
    end

    if __game_mode ~= __lib_type_campaign or (__game_mode == __lib_type_campaign and force) then
        self:save_mct_settings()
    end
end

-- only used for new games in MP
function settings:mp_load()
    mct:log("mp_load() start")
    -- first up: set up the events to respond to the MP stuff
    ClMultiplayerEvents.registerForEvent(
        "MctMpInitialLoad","MctMpInitialLoad",
        function(mct_data)
            -- mct_data = {mod_key = {option_key = {setting = xxx, read_only = true}, option_key_2 = {setting = yyy, read_only = false}}, mod_key2 = {etc}}
            mct:log("MctMpInitialLoad begun!")
            for mod_key, options in pairs(mct_data) do
                local mod_obj = mct:get_mod_by_key(mod_key)
                mct:log("Looping through mod obj ["..mod_key.."].")

                for option_key, option_data in pairs(options) do
                    
                    mct:log("At object ["..option_key.."]")
                    local option_obj = mod_obj:get_option_by_key(option_key)

                    local setting = option_data._setting

                    mct:log("Setting: "..tostring(setting))

                    option_obj:set_finalized_setting_event_free(setting)
                end
            end

            mct:log("MctMpInitialLoad end!")

            mct:log("Triggering MctInitializedMp, enjoy")
            core:trigger_custom_event("MctInitialized", {["mct"] = mct, ["is_multiplayer"] = true})
        end
    )

    --mct:log("Is this being called too early?")
    local test_faction = cm:get_saved_value("mct_host")
    mct:log("Host faction key is: "..test_faction)

    --mct:log("Local faction is: "..local_faction)

    --mct:log("Is THIS?")
    --if cm.game_interface:model():faction_is_local(test_faction) then
    if core:svr_load_bool("local_is_host") then
        mct:log("mct_host found!")
        self:load()

        local tab = {}

        local all_mods = mct:get_mods()
        for mod_key, mod_obj in pairs(all_mods) do
            tab[mod_key] = {}

            local options = mod_obj:get_options()

            for option_key, option_obj in pairs(options) do
                -- don't send local-only settings to both
                if option_obj:get_local_only() == false then
                    tab[mod_key][option_key] = {}

                    tab[mod_key][option_key]._setting = option_obj:get_finalized_setting()
                end
            end
        end

        mct:log("Triggering MctMpInitialLoad")

        ClMultiplayerEvents.notifyEvent("MctMpInitialLoad", 0, tab)
    end
end

function settings:load()
    local file = io.open(self.settings_file, "r")
    if not file then
        -- create a file with all the defaults!
        mct:log("First time load - creating settings file! Using defaults for every option.")
        self:finalize(true)
        mct:log("Settings file created, all defaults applied!")
    else
        mct:log("Loading settings file!")
        local content = loadfile(self.settings_file)
        content = content()

        local any_added = false

        --local content = table.load(self.settings_file)
        local all_mods = mct:get_mods()

        for mod_key, mod_obj in pairs(all_mods) do
            mct:log("Loading settings for mod ["..mod_key.."].")

            -- check if there's any saved data for this mod obj
            local data = content[mod_key]

            --if not mct:is_mct_mod(mod_obj) then
                --mct:error("Running settings:load(), but a mct_mod in the mct_data with key ["..mod_key.."] is not a valid mct_mod! Skipping!")
            --else
            --mod_obj._finalized_setings = data

                -- loop through all of the actual options available in the mct_mod, not only ones in the settings file
                local all_options = mod_obj:get_options()

                for option_key, option_obj in pairs(all_options) do
                    local setting = nil

                    -- grab data attached to this option key in the .lua settings file
                    if not is_nil(data) then
                        local saved_data = data[option_key]

                        -- grab the saved data in the .lua file for this option!
                        if not is_nil(saved_data) then
                            setting = saved_data._setting
                        else -- this is a new setting!
                            mct:log("New setting found! ["..option_key.."]")
                            if is_nil(self.new_settings[mod_key]) then
                                mct:log("?")
                                self.new_settings[mod_key] = {}
                                --mct:log("??")
                            end

                            --mct:log("???")

                            -- save the option key in the new_settings table, so we can look back later and see that it's new!
                            self.new_settings[mod_key][#self.new_settings[mod_key]+1] = option_key

                            --mct:log("????")

                            any_added = true

                            --mct:log("?????")
                        end
                    end

                    -- if no setting was found, default to whatever the default_value is
                    if is_nil(setting) then
                        -- this returns the default value
                        setting = option_obj:get_finalized_setting()
                    end

                    -- set the finalized setting and read only stuffs
                    option_obj:set_finalized_setting_event_free(setting)

                    mct:log("Finalizing option ["..option_key.."] with setting ["..tostring(setting).."]")
                end
                
                mod_obj:load_finalized_settings()
            --end
        end

        --mct:log("!")

        self:finalize()

        --mct:log("!!")

        --mct:log("Any added:")
        mct:log(tostring(any_added))
        if any_added then
            --mct:log("does this exist")
            mct.ui:add_ui_created_callback(function()
                local ok, err = pcall(function()
                local mod_keys = {}
                for k, _ in pairs(self.new_settings) do
                    mod_keys[#mod_keys+1] = k
                end

                local key = "mct_new_settings"
                local text = "[[col:red]]MCT - New Settings Found![[/col]]\n\nNew settings have been added since the last time you've played, in mods "

                for i = 1, #mod_keys do
                    local mod_obj = mct:get_mod_by_key(mod_keys[i])
                    local title = mod_obj:get_title()

                    -- there's only one changed mod
                    if 1 == #mod_keys then
                        text = text .. "\"" .. title .. "\"" .. ". "
                    else
                        if i == #mod_keys then
                            text = text .. "and \"" .. title .. "\"" .. ". "
                        else
                            text = text .. "\"" .. title .. "\"" .. ", "
                        end
                    end
                end

                -- TODO Localise this text entirely
                text = text .. "\nPress the check to open MCT. Or, press the x to accept all default values for the new settings."

                mct.ui:create_popup(
                    key,
                    text,
                    true, -- this uses two buttons
                    function() -- the "ok" button was triggered - show the MCT panel
                        mct.ui:open_frame()
                    end,
                    function()  -- the "cancel" button was triggered - do nuffin, really
                    end
                )
            end) if not ok then mct:log(err) end
            end)
        end
    end
end

-- load saved details for all mods 
function settings:load_game_callback(context)
    --local retval = {}

    mct:log("Loading settings from the save file!")

    local mods = mct:get_mods()

    for mod_key, mod_obj in pairs(mods) do
        local saved_data = cm:load_named_value("mct_"..mod_key, {}, context)

        mct:log("Testing for mod ["..mod_key.."]")

        -- check if there's anything actually saved for this mod key
        if is_table(saved_data) then
            mct:log("Saved data found; checking through options saved!")

            for option_key, option_data in pairs(saved_data) do
                mct:log("Testing for option ["..option_key.."].")
                local option_obj = mod_obj:get_option_by_key(option_key)
                if option_obj then
                    -- save the option details in Lua-state
                    option_obj:set_finalized_setting_event_free(option_data._setting)
                    option_obj:set_read_only(option_data._read_only)

                    mct:log("Setting: "..tostring(option_data._setting))
                    mct:log("Read only: "..tostring(option_data._read_only))
                end
            end
            mod_obj:load_finalized_settings()
        end
    end
end

--[[ TODO improve this so it
        A) triggers immediately on a new game, hard-locks settings right away
        B) triggers on all other saves, and checks if there have been any *local* edits (not on the settings.lua file, through the mods themselves!) to non-read-only settings
--]]

-- called whenever saving
function settings:save_game_callback(context)
    --local file = io.open(self.settings_file, "r")
    --if not file then
        -- ISSUE
    --else
        mct:log("Saving settings to the save file.")

        local all_mods = mct:get_mods()


        -- go through each mod in the settings file, and save a table with all the info into it
        for mod_key, mod_obj in pairs(all_mods) do
            --local mod_obj = mct:get_mod_by_key(mod_key)
            local mod_table = {}

            local options = mod_obj:get_options()

            for option_key, option_obj in pairs(options) do
                --local option_obj = mod_obj:get_option_by_key(option_key)
                if option_obj --[[and option_obj:get_read_only()]] then
                    mod_table[option_key] = {
                        _setting = option_obj:get_finalized_setting(),
                        _read_only = option_obj:get_read_only(),
                    }
                end
            end

            cm:save_named_value("mct_"..mod_key, mod_table, context)
        end
    --end
end

return settings