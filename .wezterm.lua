-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28

local pwsh = { "pwsh", "-NoLogo" }
local wsl = { "wsl", "--cd", "~/projects" }
config.max_fps = 120
-- config.default_prog = { table.unpack(pwsh), "-wd", wezterm.home_dir .. "\\IdeaProjects" }
config.default_prog = wsl

-- Attempt to respect Alt key in nvim
-- config.allow_win32_input_mode = false
-- config.enable_kitty_keyboard = true
config.skip_close_confirmation_for_processes_named =
	{ "nvim", "tmux", "pwsh.exe", "cmd.exe", "wezterm", "wslhost.exe" }
config.enable_scroll_bar = false
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = "NeverPrompt"
config.automatically_reload_config = true
config.adjust_window_size_when_changing_font_size = false
config.audible_bell = "Disabled"
config.window_background_opacity = 0.92
config.background = {
	-- {
	-- 		source = {
	-- 			File = wezterm.home_dir .. "\\Pictures\\Backgrounds\\technology-futuristic.png",
	-- 		},
	-- },
}

config.keys = {
	{
		key = "l",
		mods = "CTRL|SHIFT",
		action = wezterm.action.SpawnCommandInNewTab({
			args = wsl, -- "-e", "tmux"
		}),
	},
	{ key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnCommandInNewTab({ args = pwsh }) },
	{ key = "s", mods = "CTRL|SHIFT", action = wezterm.action.SpawnCommandInNewTab({ args = wsl }) },
	-- Attempt to respect Alt key in nvim
	-- { key = "h", mods = "ALT", action = wezterm.action.SendKey({ key = "h", mods = "ALT" }) },
	-- { key = "j", mods = "ALT", action = wezterm.action.SendKey({ key = "j", mods = "ALT" }) },
	-- { key = "k", mods = "ALT", action = wezterm.action.SendKey({ key = "k", mods = "ALT" }) },
	-- { key = "l", mods = "ALT", action = wezterm.action.SendKey({ key = "l", mods = "ALT" }) },
}

-- wezterm.on("gui-startup", function(cmd)
-- 	local _, _, window = wezterm.mux.spawn_window(cmd or {})
-- 	window:gui_window():maximize()
-- end)

-- or, changing the font size and color scheme.
config.font = wezterm.font("FiraCode Nerd Font")
config.font_size = 16
config.color_scheme = "Batman"

-- Finally, return the configuration to wezterm:
return config
