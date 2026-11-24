local Utils = require("wkwk.ng-nav.utils")

local M = {}

---Finds component classes that reference the current external template.
---Opens the result directly when there is one match, or lists multiple matches in
---the quickfix window.
---@param opts? NgNav.OpenOption Window options for opening a single result.
M.goToComponentClass = function(opts)
	opts = opts or {}
	Utils.on_angular_workspace(function()
		Utils.request_client_command("angular/getComponentsWithTemplateFile", function(_, result, client)
			if not result or #result == 0 then
				vim.notify("[Wkwk.NgNav] No component found referencing this template.", vim.log.levels.INFO)
				return
			end
			if #result == 1 then
				Utils.show_document(result[1], client.offset_encoding, opts)
			else
				vim.fn.setqflist({}, " ", {
					title = "Angular Components",
					items = vim.lsp.util.locations_to_items(result, client.offset_encoding),
				})
				vim.cmd.copen()
			end
		end)
	end)
end

return M
