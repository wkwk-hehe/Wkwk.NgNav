local Utils = require("wkwk.ng-nav.utils")

-- Type-Check Block content provider
---@class NgNav.TypeCheckBlockProvider
---@field uri? string Virtual URI identifying the current generated type-check block.
---@field bufnr? integer Scratch buffer containing the generated block.
---@field namespace integer Extmark namespace used to highlight template selections.
---@field update fun(self: NgNav.TypeCheckBlockProvider, uri: string?, content: string) Replace the scratch buffer contents and URI.
---@field show fun(self: NgNav.TypeCheckBlockProvider, ranges?: lsp.Range[]) Display the buffer and highlight its source ranges.
local provider = {
	---@type string?
	uri = nil,
	---@type integer?
	bufnr = nil,
	namespace = vim.api.nvim_create_namespace("wkwk.ng-nav"),

	---Creates the scratch buffer if needed and replaces its contents.
	---@param uri string? Virtual URI from Angular language server.
	---@param content string Generated TypeScript type-check block.
	update = function(self, uri, content)
		if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
			self.bufnr = vim.api.nvim_create_buf(false, true)
			vim.bo[self.bufnr].buftype = "nofile"
			vim.bo[self.bufnr].bufhidden = "hide"
			vim.bo[self.bufnr].swapfile = false
			vim.bo[self.bufnr].filetype = "typescript"
		end
		local normalized = type(uri) == "string" and uri:gsub("^file:///", "ng:///") or "ng:///typecheck-block"
		if self.uri ~= normalized then
			self.uri = normalized
			for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
				if buf_id ~= self.bufnr
					and vim.api.nvim_buf_is_valid(buf_id)
					and vim.api.nvim_buf_get_name(buf_id) == self.uri
				then
					vim.api.nvim_buf_delete(buf_id, { force = true })
				end
			end
			vim.api.nvim_buf_set_name(self.bufnr, self.uri)
		end
		vim.bo[self.bufnr].modifiable = true
		local lines = vim.split(content or "", "\n", { plain = true })
		vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
		vim.bo[self.bufnr].modifiable = false
		vim.bo[self.bufnr].modified = false
	end,

	---Shows the scratch buffer and highlights ranges corresponding to the template.
	---@param ranges? lsp.Range[] Source ranges to highlight in the generated block.
	show = function(self, ranges)
		if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
			return
		end
		local buf_win_id = vim.fn.bufwinid(self.bufnr)
		if buf_win_id ~= -1 then
			vim.api.nvim_set_current_win(buf_win_id)
		else
			vim.cmd.tabnew()
			vim.api.nvim_win_set_buf(0, self.bufnr)
		end
		vim.api.nvim_buf_clear_namespace(self.bufnr, self.namespace, 0, -1)
		if ranges and #ranges > 0 then
			for _, range in ipairs(ranges) do
				if range.start and range["end"] then
					vim.api.nvim_buf_set_extmark(self.bufnr, self.namespace, range.start.line, range.start.character, {
						end_row = range["end"].line,
						end_col = range["end"].character,
						hl_group = "Visual",
						priority = 100,
					})
				end
			end
			local col = ranges[1].start
			local lines_total = vim.api.nvim_buf_line_count(self.bufnr)
			local row = math.min(col.line + 1, lines_total)
			vim.api.nvim_win_set_cursor(0, { row, col.character })
		end
	end,
}

local M = {}

---Displays Angular's generated type-check block for the current template location.
---The block is shown in a reusable TypeScript scratch buffer; source selections are
---highlighted when the language server provides them.
M.viewTypeCheckBlock = function()
	Utils.on_angular_workspace(function()
		Utils.request_client_command("angular/getTcb", function(_, result)
			if not result or not result.content then
				vim.notify("[Wkwk.NgNav] No template typecheck block available here.", vim.log.levels.INFO)
				return
			end
			provider:update(result.uri, result.content)
			provider:show(result.selections)
		end)
	end)
end

return M
