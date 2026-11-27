---@meta

---@class NgNav
---@field Config NgNav.Config Active configuration table populated during `setup()`.
---@field Api NgNav.Api Public API functions for Angular project and component navigation.
---@field __Cache NgNav.Cache Internal cached values maintained by the plugin; do not modify directly.
---@field setup fun(config?: NgNav.Config): NgNav Initialize the plugin with optional configuration.

---@class NgNav.Config
---@field workspace? NgNav.Config.Workspace Workspace scanning options; omitted fields use defaults.
---@field component_files? NgNav.Config.ComponentFiles Options for the related-component-files picker.

---@class NgNav.Config.Workspace
---@field ignored_dirs? string[] Directory names to skip while discovering workspace projects.

---@class NgNav.Config.ComponentFiles
---@field default_mode? NgNav.PickerMode Initial Snacks picker mode; defaults to `insert`.
---@field keys? NgNav.ComponentFilesKeys Key bindings for opening a selected file in a split or tab.
---@field disable_multi_select? boolean Disable Snacks multi-select bindings in this picker; defaults to true.

---@class NgNav.ComponentFilesKeys
---@field split? string|false Key to open the selected file in a horizontal split; defaults to `<C-x>`.
---@field vsplit? string|false Key to open the selected file in a vertical split; defaults to `<C-v>`.
---@field tab? string|false Key to open the selected file in a new tab; defaults to `<C-t>`.

---@class NgNav.Cache
---@field ignored_dirs table<string, boolean> Internal lookup set of ignored directory names, rebuilt by `setup()`.

---@class NgNav.OpenOption
---@field split? NgNav.SplitOption Open the target in a horizontal split, vertical split, or new tab.
---@field reuseWin? boolean Focus an existing window showing the target instead of opening it again.

---@class NgNav.ComponentFilesOption: NgNav.OpenOption
---@field show_current? boolean Include the current file in the picker and mark it as current; defaults to false.
---@field mode? NgNav.PickerMode Override the configured picker mode for this call; invalid values fall back to insert.

---@alias NgNav.PickerMode "insert"|"normal"

---@alias NgNav.SplitOption
---| "split" # Open the target in a horizontal split.
---| "vsplit" # Open the target in a vertical split.
---| "tab split" # Open the target in a new tab.

---@class NgNav.Api
---@field OpenProjects fun(opts?: NgNav.OpenOption) Show a picker for projects in the current Nx/Angular workspace.
---@field ViewTypeCheckBlock fun() Show the Angular template type-check block for the current buffer.
---@field GoToComponentStylesheet fun(opts?: NgNav.OpenOption) Open the current component's stylesheet.
---@field GoToComponentTemplate fun(opts?: NgNav.OpenOption) Open the current component's template.
---@field GoToComponentClass fun(opts?: NgNav.OpenOption) Find and open component classes referencing the current template.
---@field GoToComponentFiles fun(opts?: NgNav.ComponentFilesOption) Pick among the current component's class, template, and stylesheets.

local NgNav = {}

---@type NgNav.Config
NgNav.Config = {}

NgNav.Api = {}

---@type NgNav.Cache
NgNav.__Cache = {
	ignored_dirs = {},
}

---@type NgNav.Config
local DEFAULT_CONFIG = {
	workspace = {
		ignored_dirs = { "node_modules", ".git", "dist", ".nx", ".angular" },
	},
	component_files = {
		default_mode = "insert",
		keys = {
			split = "<C-x>",
			vsplit = "<C-v>",
			tab = "<C-t>",
		},
		disable_multi_select = true,
	},
}

---Internal helper namespace
local H = {}

---Merges user configuration over `DEFAULT_CONFIG` and stores it on `NgNav.Config`.
---@param config? NgNav.Config Optional user configuration overrides.
---@return NgNav.Config config The resolved configuration table.
function H.setupConfig(config)
	config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
	NgNav.Config = config
	local ignored_dirs = {}
	for _, name in ipairs(config.workspace.ignored_dirs or {}) do
		ignored_dirs[name] = true
	end
	NgNav.__Cache.ignored_dirs = ignored_dirs
	return config
end

---Registers lazy-loaded wrappers on `NgNav.Api` so submodules are only required
---when their corresponding API method is first called.
local function setupApi()
	---Opens the Angular projects picker/view.
	---@param opts? NgNav.OpenOption
	NgNav.Api.OpenProjects = function(opts)
		require("wkwk.ng-nav.api.open-projects").openProjects(opts)
	end

	---Jumps to the Angular type-check block (TCB).
	NgNav.Api.ViewTypeCheckBlock = function()
		require("wkwk.ng-nav.api.view-tcb").viewTypeCheckBlock()
	end

	---Navigates to the current component's stylesheet file.
	---@param opts? NgNav.OpenOption
	NgNav.Api.GoToComponentStylesheet = function(opts)
		require("wkwk.ng-nav.api.goto-style").goToComponentStylesheet(opts)
	end

	---Navigates to the current component's template file.
	---@param opts? NgNav.OpenOption
	NgNav.Api.GoToComponentTemplate = function(opts)
		require("wkwk.ng-nav.api.goto-template").goToComponentTemplate(opts)
	end

	---Navigates to the current component's class file.
	---@param opts? NgNav.OpenOption
	NgNav.Api.GoToComponentClass = function(opts)
		require("wkwk.ng-nav.api.goto-class").goToComponentClass(opts)
	end

	---Picks between the current component's class, template, and stylesheets.
	---@param opts? NgNav.ComponentFilesOption
	NgNav.Api.GoToComponentFiles = function(opts)
		require("wkwk.ng-nav.api.goto-component-files").goToComponentFiles(opts)
	end
end

---@param config? NgNav.Config user configuration overrides.
---@return NgNav self The initialized `NgNav` module instance.
NgNav.setup = function(config)
	-- Expose module globally under `_G.Wkwk.NgNav` for external/command access.
	_G.Wkwk = _G.Wkwk or {}
	_G.Wkwk.NgNav = NgNav

	-- Merge and persist configuration.
	H.setupConfig(config)

	-- Wire up lazy-loaded API entrypoints.
	setupApi()

	return NgNav
end

return NgNav
