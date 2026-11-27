local Utils = require("wkwk.ng-nav.utils")

local M = {}

local STYLE_EXTENSIONS = { scss = true, sass = true, css = true, less = true }

local function is_stylesheet(path)
	local extension = path:match("%.([^./]+)$")
	return extension ~= nil and STYLE_EXTENSIONS[extension:lower()] == true
end

---Finds and opens stylesheets associated with the current component, template, or stylesheet.
---Uses component metadata first, then conventional sibling stylesheet names; prompts
---for a choice when multiple matching files are found, excluding the current stylesheet.
---@param opts? NgNav.OpenOption Window options for opening a stylesheet.
M.goToComponentStylesheet = function(opts)
	opts = opts or {}
	local current_path = vim.api.nvim_buf_get_name(0)
	if current_path == "" then
		vim.notify("[Wkwk.NgNav] Current buffer has no file path.", vim.log.levels.WARN)
		return
	end
	current_path = vim.fs.normalize(current_path)

	local styles
	if is_stylesheet(current_path) then
		local class_path = Utils.get_component_class_path(current_path)
		styles = Utils.find_associated_stylesheets(class_path or current_path)
	else
		styles = Utils.find_associated_stylesheets(current_path)
	end
	local other_styles = {}
	for _, style in ipairs(styles) do
		if vim.fs.normalize(style) ~= current_path then
			table.insert(other_styles, style)
		end
	end
	if is_stylesheet(current_path) then
		if #other_styles == 0 then
			vim.notify("[Wkwk.NgNav] Already in a component stylesheet.", vim.log.levels.INFO)
			return
		end
		styles = other_styles
	end
	if #styles == 0 then
		vim.notify("[Wkwk.NgNav] No related component stylesheet found.", vim.log.levels.INFO)
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
