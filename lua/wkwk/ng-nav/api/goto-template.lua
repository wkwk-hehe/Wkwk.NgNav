local Utils = require("wkwk.ng-nav.utils")

local M = {}

---Navigates from the current Angular component class to its template.
---@param opts? NgNav.OpenOption Window options for opening the template.
M.goToComponentTemplate = function(opts)
	opts = opts or {}
	Utils.on_angular_workspace(function()
		Utils.request_client_command("angular/getTemplateLocationForComponent", function(_, result, client)
			if not result then
				vim.notify("[Wkwk.NgNav] No template found for component.", vim.log.levels.INFO)
				return
			end
			local target = vim.islist(result) and result[1] or result
			if target then
				Utils.show_document(target, client.offset_encoding, opts)
			end
		end)
	end)
end

return M
