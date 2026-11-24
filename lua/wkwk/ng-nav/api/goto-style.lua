local Utils = require("wkwk.ng-nav.utils")

local M = {}

---Finds and opens stylesheets associated with the current component or template.
---Uses component metadata first, then conventional sibling stylesheet names; prompts
---for a choice when multiple matching files are found.
---@param opts? NgNav.OpenOption Window options for opening a stylesheet.
M.goToComponentStylesheet = function(opts)
	opts = opts or {}
	local current_path = vim.api.nvim_buf_get_name(0)
	if current_path == "" then
		vim.notify("[Wkwk.NgNav] Current buffer has no file path.", vim.log.levels.WARN)
		return
	end

	local styles = Utils.find_associated_stylesheets(current_path)
	if #styles == 0 then
		vim.notify("[Wkwk.NgNav] No stylesheet found.", vim.log.levels.INFO)
		return
	end

	if #styles == 1 then
		Utils.open_uri(styles[1], opts)
	else
		vim.ui.select(styles, {
			prompt = "Select stylesheet:",
			format_item = function(item)
				return vim.fn.fnamemodify(item, ":t")
			end,
		}, function(choice)
			if choice then
				Utils.open_uri(choice, opts)
			end
		end)
	end
end

return M
