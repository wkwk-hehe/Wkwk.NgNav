local Utils = require("wkwk.ng-nav.utils")

local M = {}

local STYLE_EXTENSIONS = { "scss", "sass", "css", "less" }
local STYLE_EXTENSION_SET = {}
for _, extension in ipairs(STYLE_EXTENSIONS) do
	STYLE_EXTENSION_SET[extension] = true
end

---@class NgNav.ComponentFile
---@field path string Absolute file path.
---@field name string File name shown in the picker.
---@field extension string Lowercase file extension.
---@field is_current boolean Whether this is the current buffer's file.

---@alias NgNav.ComponentFileChunk { [1]: string, [2]?: string }

---@class NgNav.ComponentFilePickerOptions
---@field prompt? string Picker title.
---@field format_item fun(file: NgNav.ComponentFile, supports_chunks?: boolean): string|NgNav.ComponentFileChunk[] Formats plain text or Snacks-highlighted chunks.
---@field snacks? { focus?: "input"|"list" } Snacks picker configuration; input focus starts in insert mode and list focus starts in normal mode.

---@alias NgNav.ComponentFilePickerSelect fun(items: NgNav.ComponentFile[], opts: NgNav.ComponentFilePickerOptions, on_choice: fun(choice?: NgNav.ComponentFile, idx?: integer))

---@param path string
---@return string?
local function get_extension(path)
	local extension = path:match("%.([^./]+)$")
	return extension and extension:lower() or nil
end

---@param location table
---@return string?
local function location_path(location)
	if type(location) ~= "table" then
		return nil
	end
	local uri = location.uri or location.targetUri
	if type(uri) ~= "string" then
		return nil
	end
	local ok, path = pcall(vim.uri_to_fname, uri)
	if ok then
		return vim.fs.normalize(path)
	end
	return nil
end

---@param path string
---@return string
local function get_component_base(path)
	return path:gsub("%.[^.]+$", "")
end

---@param path string
---@return string?
local function get_template_path(path)
	local base = get_component_base(path)
	if vim.fn.filereadable(base .. ".html") == 1 then
		return base .. ".html"
	end
	return nil
end

---@param path string
---@return string?
local function get_class_path(path)
	local base = get_component_base(path)
	if vim.fn.filereadable(base .. ".ts") == 1 then
		return base .. ".ts"
	end
	return nil
end

---@param path string
---@return string?
local function get_icon(path)
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if not ok or type(devicons.get_icon) ~= "function" then
		return nil
	end
	local name = vim.fs.basename(path)
	local extension = get_extension(path)
	local icon_ok, icon = pcall(devicons.get_icon, name, extension)
	if icon_ok and type(icon) == "string" and icon ~= "" then
		return icon
	end
	return nil
end

---@param file NgNav.ComponentFile
---@param supports_chunks? boolean
---@return string|NgNav.ComponentFileChunk[]
local function format_file(file, supports_chunks)
	local extension = file.extension
	local highlight = extension == "html" and "DiagnosticWarn"
		or extension == "ts" and "DiagnosticInfo"
		or (extension == "scss" or extension == "sass" or extension == "less") and "Special"
		or extension == "css" and "DiagnosticHint"
	local icon = get_icon(file.path) or ("[" .. extension .. "]")
	local current_label = file.is_current and " [current]" or ""
	local display_path = vim.fn.fnamemodify(file.path, ":~:.")

	if supports_chunks then
		local chunks = {
			{ icon .. " ", highlight },
			{ file.name, highlight },
		}
		if file.is_current then
			table.insert(chunks, { current_label, "IncSearch" })
		end
		table.insert(chunks, { " — " .. display_path })
		return chunks
	end

	return string.format("%s %s%s — %s", icon, file.name, current_label, display_path)
end

---@param files NgNav.ComponentFile[]
---@param opts NgNav.ComponentFilesOption
local function show_picker(files, opts)
	if #files == 0 then
		vim.notify("[Wkwk.NgNav] No related component files found.", vim.log.levels.INFO)
		return
	end

	-- Snacks supports highlighted chunks; standard vim.ui.select receives plain text.
	local select = vim.ui.select --[[@as NgNav.ComponentFilePickerSelect]]
	select(files, {
		prompt = "Select component file:",
		-- Snacks maps list focus to normal mode and input focus to insert mode.
		-- Invalid values intentionally fall back to the usual insert-mode prompt.
		snacks = {
			focus = opts.mode == "normal" and "list" or "input",
		},
		format_item = function(file, supports_chunks)
			return format_file(file, supports_chunks)
		end,
	}, function(choice)
		if choice then
			vim.schedule(function()
				Utils.open_uri(choice.path, opts)
			end)
		end
	end)
end

---@param opts? NgNav.ComponentFilesOption
M.goToComponentFiles = function(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local current_path = vim.api.nvim_buf_get_name(bufnr)
	if current_path == "" then
		vim.notify("[Wkwk.NgNav] Current buffer has no file path.", vim.log.levels.WARN)
		return
	end
	current_path = vim.fs.normalize(current_path)

	local files = {}
	local seen = {}
	local function add_file(path, is_current)
		path = vim.fs.normalize(path)
		if not is_current and vim.fn.filereadable(path) ~= 1 then
			return
		end
		if seen[path] then
			if is_current then
				seen[path].is_current = true
			end
			return
		end
		local extension = get_extension(path)
		if extension ~= "ts" and extension ~= "html" and not STYLE_EXTENSION_SET[extension] then
			return
		end
		local file = {
			path = path,
			name = vim.fs.basename(path),
			extension = extension,
			is_current = is_current == true,
		}
		seen[path] = file
		table.insert(files, file)
	end

	local function add_stylesheets(class_path, template_path)
		for _, path in ipairs(Utils.find_associated_stylesheets(class_path)) do
			add_file(path)
		end
		if template_path then
			for _, path in ipairs(Utils.find_associated_stylesheets(template_path)) do
				add_file(path)
			end
		end
	end

	local function add_class(path)
		add_file(path)
		local template_path = get_template_path(path)
		if template_path then
			add_file(template_path)
		end
		add_stylesheets(path, template_path)
	end

	local function add_template(path)
		add_file(path)
		local class_path = get_class_path(path)
		if class_path then
			add_class(class_path)
		else
			for _, style_path in ipairs(Utils.find_associated_stylesheets(path)) do
				add_file(style_path)
			end
		end
	end

	local function add_stylesheet(path)
		add_file(path)
		local class_path = get_class_path(path)
		local template_path = get_template_path(path)
		if class_path then
			add_class(class_path)
		elseif template_path then
			add_template(template_path)
		end
	end

	local current_extension = get_extension(current_path)
	local current_is_class = current_extension == "ts"
	local current_is_template = current_extension == "html"
	local current_is_stylesheet = STYLE_EXTENSION_SET[current_extension]

	if current_is_class then
		add_class(current_path)
		local template_path = get_template_path(current_path)
		if template_path then
			add_template(template_path)
		end
	elseif current_is_template then
		add_template(current_path)
	elseif current_is_stylesheet then
		add_stylesheet(current_path)
	end

	if opts.show_current then
		add_file(current_path, true)
	end

	local function finish()
		if opts.show_current then
			add_file(current_path, true)
		else
			seen[current_path] = nil
			for index = #files, 1, -1 do
				if files[index].path == current_path then
					table.remove(files, index)
				end
			end
		end
		show_picker(files, opts)
	end

	local command
	if current_is_class then
		command = "angular/getTemplateLocationForComponent"
	elseif current_is_template then
		command = "angular/getComponentsWithTemplateFile"
	end
	if not command then
		finish()
		return
	end

	Utils.on_angular_workspace(function()
		Utils.request_client_command(command, function(_, result)
			local locations = vim.islist(result) and result or result and { result } or {}
			for _, location in ipairs(locations) do
				local path = location_path(location)
				if path then
					if current_is_class then
						add_template(path)
					else
						add_class(path)
					end
				end
			end
			finish()
		end, function()
			finish()
		end)
	end, function()
		finish()
	end)
end

return M
