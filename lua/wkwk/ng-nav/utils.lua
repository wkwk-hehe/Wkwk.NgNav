--- Extracts `styleUrl` or `styleUrls` paths from a component TypeScript file.
---@param ts_path string
---@return string[]
local function parse_style_file_urls(ts_path)
	if vim.fn.filereadable(ts_path) ~= 1 then
		return {}
	end
	local content = table.concat(vim.fn.readfile(ts_path), "\n")
	local dir = vim.fs.dirname(ts_path)
	local found = {}
	-- Match singular: styleUrl: './foo.scss' or styleUrl: "./foo.scss"
	local single = content:match("styleUrl%s*:%s*['\"]([^'\"]+)['\"]")
	if single then
		local full = vim.fs.normalize(vim.fs.joinpath(dir, single))
		if vim.fn.filereadable(full) == 1 then
			table.insert(found, full)
		end
	end

	-- Match plural: styleUrls: ['./foo.scss', './bar.css']
	local array_body = content:match("styleUrls%s*:%s*%[(.-)%]")
	if array_body then
		for rel in array_body:gmatch("['\"]([^'\"]+)['\"]") do
			local full = vim.fs.normalize(vim.fs.joinpath(dir, rel))
			if vim.fn.filereadable(full) == 1 and not vim.tbl_contains(found, full) then
				table.insert(found, full)
			end
		end
	end
	return found
end

local STYLE_EXTENSIONS = { "scss", "sass", "css", "less" }

---@class NgNav.Utils
---@field show_document fun(location: lsp.Location|lsp.LocationLink, offset_encoding: string, opts?: NgNav.OpenOption) Open an LSP location, optionally in a split or tab.
---@field open_uri fun(path: string, opts?: NgNav.OpenOption) Open a file or directory path, optionally in a split or tab.
---@field find_associated_stylesheets fun(filepath: string): string[] Find existing component stylesheets for a TypeScript or HTML file.
---@field get_angular_lsp_client fun(bufnr: integer): vim.lsp.Client? Get the Angular language server attached to a buffer, if any.
---@field request_client_command fun(command: string, callback: fun(err: lsp.ResponseError?, result: any, client: vim.lsp.Client), on_error?: fun(err: lsp.ResponseError|string)) Send an Angular LSP command and handle its response.
---@field on_angular_workspace fun(callback: fun(), on_error?: fun(err: lsp.ResponseError|string)) Run a callback only when the current buffer belongs to an Angular workspace.

local M = {}

---Opens an LSP location or location link, optionally in a split or a new tab.
---@param location lsp.Location|lsp.LocationLink LSP location to display.
---@param offset_encoding string Encoding used for positions in the location.
---@param opts? NgNav.OpenOption Window options for opening the location.
function M.show_document(location, offset_encoding, opts)
	opts = opts or {}
	if opts.split == "vsplit" then
		vim.cmd({ cmd = "vsplit" })
	elseif opts.split == "split" then
		vim.cmd({ cmd = "split" })
	elseif opts.split == "tab split" then
		vim.cmd({ cmd = "tabnew" })
	end
	vim.lsp.util.show_document(location, offset_encoding, {
		-- Do not jump back to an old window if the user explicitly asked for a new split
		reuse_win = opts.split == nil and (opts.reuseWin or false) or false,
		focus = true,
	})
end

---Opens a file or directory path, optionally in a split or a new tab.
---@param uri string File or directory path to open.
---@param opts? NgNav.OpenOption Window options for opening the path.
function M.open_uri(uri, opts)
	opts = opts or {}
	local normalized = vim.fs.normalize(uri)
	if opts.split == "vsplit" then
		vim.cmd({ cmd = "vsplit", args = { normalized } })
		return
	elseif opts.split == "split" then
		vim.cmd({ cmd = "split", args = { normalized } })
		return
	elseif opts.split == "tab split" then
		vim.cmd({ cmd = "tabedit", args = { normalized } })
		return
	end
	if opts.reuseWin then
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == normalized then
				for _, winid in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(winid) == bufnr then
						vim.api.nvim_set_current_win(winid)
						return
					end
				end
			end
		end
	end
	vim.cmd({ cmd = "edit", args = { normalized } })
end

---Finds existing component stylesheets from metadata or conventional sibling names.
---@param filepath string TypeScript component or HTML template path.
---@return string[] Existing stylesheet paths with `.scss`, `.sass`, `.css`, or `.less` extensions.
function M.find_associated_stylesheets(filepath)
	local matches = {}
	-- 1. If current file is a component TS file, inspect `styleUrl` / `styleUrls` first
	if filepath:match("%.ts$") then
		matches = parse_style_file_urls(filepath)
		if #matches > 0 then
			return matches
		end
	end
	-- 2. Check conventional sibling files (e.g. foo.component.scss / foo.scss)
	local base = filepath:gsub("%.component%.[^.]+$", ".component")
	if base == filepath then
		base = filepath:gsub("%.[^.]+$", "")
	end
	for _, ext in ipairs(STYLE_EXTENSIONS) do
		local candidate = base .. "." .. ext
		if vim.fn.filereadable(candidate) == 1 then
			table.insert(matches, candidate)
		end
	end
	-- 3. If started from an HTML template with non-standard names, check sibling .component.ts metadata
	if #matches == 0 and filepath:match("%.html$") then
		local sibling_ts = base .. ".ts"
		matches = parse_style_file_urls(sibling_ts)
	end
	return matches
end

---Retrieves the active Angular language server attached to a buffer.
---@param bufnr integer Buffer to inspect.
---@return vim.lsp.Client? Angular language server client, or nil if none is attached.
function M.get_angular_lsp_client(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "angularls" })
	if #clients > 0 then
		return clients[1]
	end
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.name:find("angular", 1, true) then
			return client
		end
	end
	return nil
end

---Sends a custom command to the Angular language server for the current cursor position.
---@param command string Angular language server command name.
---@param callback fun(err: lsp.ResponseError?, result: any, client: vim.lsp.Client) Called with the response and client on success.
---@param on_error? fun(err: lsp.ResponseError|string) Called if no client is attached, the request fails, or it cannot be sent.
function M.request_client_command(command, callback, on_error)
	local bufnr = vim.api.nvim_get_current_buf()
	local client = M.get_angular_lsp_client(bufnr)
	if not client then
		vim.notify("[Wkwk.NgNav] No Angular language server attached to current buffer.", vim.log.levels.WARN)
		if on_error then
			on_error("No Angular language server attached to current buffer.")
		end
		return
	end
	local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
	local sent = client:request(command, params, function(err, result)
		if err then
			vim.notify(string.format("[Wkwk.NgNav] %s failed: %s", command, err.message or tostring(err)),
				vim.log.levels.ERROR)
			if on_error then
				on_error(err)
			end
			return
		end
		callback(err, result, client)
	end, bufnr)
	if not sent then
		local err = string.format("Could not send %s request.", command)
		vim.notify("[Wkwk.NgNav] " .. err, vim.log.levels.ERROR)
		if on_error then
			on_error(err)
		end
	end
end

---Checks Angular workspace membership before running a callback.
---@param callback fun() Called only when the current buffer belongs to an Angular workspace.
---@param on_error? fun(err: lsp.ResponseError|string) Called if the check fails or the buffer is outside a workspace.
M.on_angular_workspace = function(callback, on_error)
	M.request_client_command("angular/isAngularCoreInOwningProject", function(_, yesItIs)
		if not yesItIs then
			vim.notify("[Wkwk.NgNav] Current file is not part of an Angular project.", vim.log.levels.INFO)
			if on_error then
				on_error("Current file is not part of an Angular project.")
			end
			return
		end
		callback()
	end, on_error)
end

return M
