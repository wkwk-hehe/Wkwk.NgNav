local Utils = require("wkwk.ng-nav.utils")

local M = {}

---Navigates to the related template from a component class or stylesheet.
---Uses sibling/metadata resolution when the current buffer is not supported by Angular LS.
---@param opts? NgNav.OpenOption Window options for opening the template.
M.goToComponentTemplate = function(opts)
	opts = opts or {}
	local current_path = vim.api.nvim_buf_get_name(0)
	if current_path == "" then
		vim.notify("[Wkwk.NgNav] Current buffer has no file path.", vim.log.levels.WARN)
		return
	end
	current_path = vim.fs.normalize(current_path)

	if current_path:match("%.html$") then
		vim.notify("[Wkwk.NgNav] Already in a template file.", vim.log.levels.INFO)
		return
	end

	if not current_path:match("%.ts$") then
		local template_path = Utils.get_component_template_path(current_path)
		if template_path then
			Utils.open_uri(template_path, opts)
		else
			vim.notify("[Wkwk.NgNav] No related component template found.", vim.log.levels.INFO)
		end
		return
	end

	local fallback_template = Utils.get_component_template_path(current_path)
	if not Utils.get_angular_lsp_client(vim.api.nvim_get_current_buf()) and fallback_template then
		Utils.open_uri(fallback_template, opts)
		return
	end

	Utils.on_angular_workspace(function()
		Utils.request_client_command("angular/getTemplateLocationForComponent", function(_, result, client)
			if not result then
				if fallback_template then
					Utils.open_uri(fallback_template, opts)
				else
					vim.notify("[Wkwk.NgNav] No related component template found.", vim.log.levels.INFO)
				end
				return
			end
			local target = vim.islist(result) and result[1] or result
			if target then
				local uri = target.uri or target.targetUri
				local ok, target_path = pcall(vim.uri_to_fname, uri)
				if not ok then
					target_path = nil
				end
				if target_path and vim.fs.normalize(target_path) == current_path then
					vim.notify("[Wkwk.NgNav] Already in this component template.", vim.log.levels.INFO)
					return
				end
				Utils.show_document(target, client.offset_encoding, opts)
			end
		end)
	end, function()
		if fallback_template then
			Utils.open_uri(fallback_template, opts)
		end
	end)
end

return M
