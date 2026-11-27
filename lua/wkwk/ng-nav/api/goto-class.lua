local Utils = require("wkwk.ng-nav.utils")

local M = {}

local STYLE_EXTENSIONS = { scss = true, sass = true, css = true, less = true }

local function is_stylesheet(path)
	local extension = path:match("%.([^./]+)$")
	return extension ~= nil and STYLE_EXTENSIONS[extension:lower()] == true
end

---Navigates to the related component class from a stylesheet or external template.
---Opens the result directly when there is one match, or lists multiple matches in
---the quickfix window when Angular LS reports multiple components.
---@param opts? NgNav.OpenOption Window options for opening a single result.
M.goToComponentClass = function(opts)
	opts = opts or {}
	local current_path = vim.api.nvim_buf_get_name(0)
	if current_path == "" then
		vim.notify("[Wkwk.NgNav] Current buffer has no file path.", vim.log.levels.WARN)
		return
	end
	current_path = vim.fs.normalize(current_path)
	local current_is_stylesheet = is_stylesheet(current_path)

	if current_path:match("%.component%.ts$") then
		vim.notify("[Wkwk.NgNav] Already in a component class file.", vim.log.levels.INFO)
		return
	end
	if current_path:match("%.ts$") and Utils.get_component_template_path(current_path) then
		vim.notify("[Wkwk.NgNav] Already in a component class file.", vim.log.levels.INFO)
		return
	end
	if current_is_stylesheet then
		local class_path = Utils.get_component_class_path(current_path)
		if class_path then
			Utils.open_uri(class_path, opts)
		else
			vim.notify("[Wkwk.NgNav] No related component class found for this stylesheet.", vim.log.levels.INFO)
		end
		return
	end

	if current_path:match("%.html$") then
		local sibling_class = Utils.get_component_class_path(current_path)
		if not Utils.get_angular_lsp_client(vim.api.nvim_get_current_buf()) and sibling_class then
			Utils.open_uri(sibling_class, opts)
			return
		end
	end

	Utils.on_angular_workspace(function()
		Utils.request_client_command("angular/getComponentsWithTemplateFile", function(_, result, client)
			if not result or #result == 0 then
				local sibling_class = Utils.get_component_class_path(current_path)
				if sibling_class then
					Utils.open_uri(sibling_class, opts)
				else
					vim.notify("[Wkwk.NgNav] No related component class found.", vim.log.levels.INFO)
				end
				return
			end
			if #result == 1 then
				local uri = result[1].uri or result[1].targetUri
				local ok, target_path = pcall(vim.uri_to_fname, uri)
				if not ok then
					target_path = nil
				end
				if target_path and vim.fs.normalize(target_path) == current_path then
					vim.notify("[Wkwk.NgNav] Already in this component class.", vim.log.levels.INFO)
					return
				end
				Utils.show_document(result[1], client.offset_encoding, opts)
			else
				vim.fn.setqflist({}, " ", {
					title = "Angular Components",
					items = vim.lsp.util.locations_to_items(result, client.offset_encoding),
				})
				vim.cmd.copen()
			end
		end)
	end, function()
		local sibling_class = Utils.get_component_class_path(current_path)
		if sibling_class then
			Utils.open_uri(sibling_class, opts)
		end
	end)
end

return M
