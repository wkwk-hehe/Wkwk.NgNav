local Utils = require("wkwk.ng-nav.utils")
local NgNav = require("wkwk.ng-nav")

---Finds the nearest Nx or Angular workspace root by searching upward.
---@param start_path string File or directory path from which to begin searching.
---@return string? Workspace root path, or nil if no marker is found.
local function find_nx_root(start_path)
	local search_start = start_path
	if search_start == "" then
		search_start = vim.fn.getcwd()
	elseif vim.fn.isdirectory(search_start) == 0 then
		search_start = vim.fs.dirname(search_start)
	end
	local nx_marker = vim.fs.find({ "nx.json", "angular.json" }, {
		path = search_start,
		upward = true,
		limit = 1,
	})[1]
	if not nx_marker then
		return nil
	end
	return vim.fs.dirname(nx_marker)
end

---Reads and decodes a JSON file, returning nil for missing or invalid files.
---@param filepath string Path to the JSON file.
---@return table? Decoded JSON object, or nil when it cannot be read or decoded.
local function read_json_file(filepath)
	if vim.fn.filereadable(filepath) ~= 1 then
		return nil
	end
	local raw = table.concat(vim.fn.readfile(filepath), "\n")
	if raw == "" then
		return nil
	end
	local ok, decoded = pcall(vim.json.decode, raw)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

local function getIgnoredDirs()
	return NgNav.__Cache.ignored_dirs
end

---Collects and sorts projects found in Nx `project.json` and Angular `angular.json` files.
---@param root string Nx or Angular workspace root.
---@return { name: string, path: string, rel_path: string, project_type: string }[] Projects with paths and display metadata.
local function discover_nx_projects(root)
	local projects = {}
	local seen_paths = {}
	local ignored_dirs = getIgnoredDirs()

	local function scan_dir(dir)
		for name, entry_type in vim.fs.dir(dir) do
			if not ignored_dirs[name] then
				local full_path = vim.fs.joinpath(dir, name)
				if entry_type == "directory" then
					scan_dir(full_path)
				elseif entry_type == "file" and name == "project.json" then
					local data = read_json_file(full_path)
					local proj_dir = dir
					local target_path = proj_dir

					if data and type(data.sourceRoot) == "string" and data.sourceRoot ~= "" then
						local candidate_source = vim.fs.normalize(vim.fs.joinpath(root, data.sourceRoot))
						if vim.fn.isdirectory(candidate_source) == 1 then
							target_path = candidate_source
						end
					end

					target_path = vim.fs.normalize(target_path)
					if not seen_paths[target_path] then
						seen_paths[target_path] = true
						local proj_name = (data and type(data.name) == "string" and data.name ~= "") and data.name
							or vim.fs.basename(proj_dir)
						local proj_type = (data and type(data.projectType) == "string" and data.projectType ~= "")
								and data.projectType
							or "project"

						local rel_path = vim.fs.relpath(root, target_path) or target_path
						table.insert(projects, {
							name = proj_name,
							path = target_path,
							rel_path = rel_path,
							project_type = proj_type,
						})
					end
				end
			end
		end
	end
	scan_dir(root)

	-- Supplement project.json discovery with angular.json projects.
	local angular_json = read_json_file(vim.fs.joinpath(root, "angular.json"))
	if angular_json and type(angular_json.projects) == "table" then
		for proj_name, proj_cfg in pairs(angular_json.projects) do
			if type(proj_cfg) == "table" then
				local sub_path = proj_cfg.sourceRoot or proj_cfg.root
				if type(sub_path) == "string" and sub_path ~= "" then
					local full_path = vim.fs.normalize(vim.fs.joinpath(root, sub_path))
					if vim.fn.isdirectory(full_path) == 1 and not seen_paths[full_path] then
						seen_paths[full_path] = true
						table.insert(projects, {
							name = proj_name,
							path = full_path,
							rel_path = vim.fs.relpath(root, full_path) or full_path,
							project_type = proj_cfg.projectType or "project",
						})
					end
				end
			end
		end
	end

	table.sort(projects, function(a, b)
		if a.project_type ~= b.project_type then
			return a.project_type < b.project_type
		end
		return a.name:lower() < b.name:lower()
	end)

	return projects
end

local function get_angular_icon()
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if not ok or type(devicons.get_icon) ~= "function" then
		return nil
	end
	local icon_ok, icon = pcall(devicons.get_icon, "angular.json", "json")
	if icon_ok and type(icon) == "string" and icon ~= "" then
		return icon
	end
	return nil
end

---@class NgNav.Project
---@field name string Display name from project metadata or its directory.
---@field path string Directory opened when the project is selected.
---@field rel_path string Path relative to the workspace root for display.
---@field project_type string Project type from metadata, such as `application` or `library`.

---A Snacks picker display chunk: text followed by an optional highlight group.
---@alias NgNav.ProjectPickerChunk { [1]: string, [2]?: string }

---@class NgNav.ProjectPickerOptions
---@field prompt? string Text shown above the project list.
---@field format_item fun(project: NgNav.Project, supports_chunks?: boolean): string|NgNav.ProjectPickerChunk[] Formats plain text or Snacks-highlighted chunks.

---@alias NgNav.ProjectPickerSelect fun(items: NgNav.Project[], opts: NgNav.ProjectPickerOptions, on_choice: fun(choice?: NgNav.Project, idx?: integer))

---Formats a project row, returning colored chunks only for chunk-aware pickers.
---@param project NgNav.Project Project to display.
---@param angular_icon? string Angular icon returned by `nvim-web-devicons`, if available.
---@param supports_chunks? boolean Whether the active picker supports highlighted chunks.
---@return string|NgNav.ProjectPickerChunk[] Plain text or picker-formatted display chunks.
local function format_project(project, angular_icon, supports_chunks)
	local project_type = tostring(project.project_type or "project"):lower()
	local fallback_icon = project_type == "application" and "🔴" or project_type == "library" and "🟡" or "⚪"
	local icon = angular_icon or fallback_icon
	local type_label = project_type == "application" and "[app]" or project_type == "library" and "[lib]" or "[???]"
	if supports_chunks then
		-- Snacks supports per-segment highlights; keep the type label and path uncolored.
		local highlight = project_type == "application" and "DiagnosticError"
			or project_type == "library" and "DiagnosticWarn"
		return {
			{ icon .. " ", highlight },
			{ type_label .. " " },
			{ project.name, highlight },
			{ " —-> " .. project.rel_path },
		}
	end
	return string.format("%s %s %s —-> %s", icon, type_label, project.name, project.rel_path)
end

local M = {}

---Opens a picker for projects in the nearest Nx or Angular workspace.
---@param opts? NgNav.OpenOption Window options for opening the selected project directory.
M.openProjects = function(opts)
	local current_path = vim.api.nvim_buf_get_name(0)
	local root = find_nx_root(current_path)
	if not root then
		vim.notify("[Wkwk.NgNav] No Nx/Angular workspace root found.", vim.log.levels.INFO)
		return
	end
	local projects = discover_nx_projects(root)
	if #projects == 0 then
		vim.notify("[Wkwk.NgNav] No projects found in Nx workspace.", vim.log.levels.INFO)
		return
	end
	local angular_icon = get_angular_icon()
	-- Snacks passes `supports_chunks`; standard vim.ui.select implementations get plain text.
	-- The cast describes Snacks' extension to vim.ui.select's narrower built-in type.
	local select = vim.ui.select --[[@as NgNav.ProjectPickerSelect]]
	select(projects, {
		prompt = "Select project:",
		format_item = function(project, supports_chunks)
			return format_project(project, angular_icon, supports_chunks)
		end,
	}, function(choice)
		if choice and choice.path then
			vim.schedule(function()
				Utils.open_uri(choice.path, opts)
			end)
		end
	end)
end

return M
