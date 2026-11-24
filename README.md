# Wkwk.NgNav

Just to make my Angular Project/Workspace navigation a lot better using Neovim :)

## Requirements

- Neovim using the current API (latest Neovim recommended).
- An Angular workspace, or an Nx workspace containing Angular projects.
- Angular Language Server (`angularls`) attached to the current buffer for template, component-class, and type-check-block navigation.

Optional integrations:

- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) provides the Angular icon in the project picker. A type-based icon is used when the plugin is unavailable.
- [snacks.nvim](https://github.com/folke/snacks.nvim) can provide a richer project picker. If `vim.ui.select` is set to `Snacks.picker.select`, app and library icons and names use `DiagnosticError` and `DiagnosticWarn` highlights. Other `vim.ui.select` implementations receive plain-text rows.

## Setup

Add the plugin to Neovim's runtime path with your preferred plugin manager, then call `setup()`:

```lua
-- example with using default options
local ng_nav = require("wkwk.ng-nav").setup({
  workspace = {
    ignored_dirs = {
      "node_modules",
      ".git",
      "dist",
      ".nx",
      ".angular",
    },
  },
})
```

## API

The public functions are available from `NgNav.Api`:

```lua
local ng_nav = require("wkwk.ng-nav").setup()

ng_nav.Api.OpenProjects()
ng_nav.Api.GoToComponentTemplate()
ng_nav.Api.GoToComponentStylesheet()
ng_nav.Api.GoToComponentClass()
ng_nav.Api.ViewTypeCheckBlock()
```

The first four functions accept optional window options:

```lua
ng_nav.Api.GoToComponentTemplate({ split = "vsplit" })
ng_nav.Api.GoToComponentStylesheet({ split = "tab split" })
ng_nav.Api.GoToComponentClass({ split = "split" })
ng_nav.Api.GoToComponentStylesheet({ reuseWin = true })
```

### Functions

| Function | Behavior |
| --- | --- |
| `OpenProjects(opts?)` | Finds the nearest `nx.json` or `angular.json`, discovers projects, and opens the selected project directory. |
| `GoToComponentTemplate(opts?)` | Uses Angular Language Server to open the current component's template. |
| `GoToComponentStylesheet(opts?)` | Finds stylesheet paths from component metadata or conventional sibling filenames. If multiple files match, prompts for one. |
| `GoToComponentClass(opts?)` | Finds component classes referencing the current external template. Opens one match or lists multiple matches in the quickfix window. |
| `ViewTypeCheckBlock()` | Displays Angular's generated template type-check block in a reusable TypeScript scratch buffer. |

## Project discovery

Project discovery starts from the current file's directory and searches upward for `nx.json` or `angular.json`. If the current buffer has no file path, it starts from Neovim's current working directory.

The picker:

- Recursively finds Nx `project.json` files, skipping configured ignored directory names.
- Supplements those results with projects in the workspace's `angular.json`.
- Uses a project's existing `sourceRoot` as its selected directory when available; otherwise uses its project root.
- Shows the project name, type, and workspace-relative path.

## Angular Language Server

Template, component-class, and type-check-block navigation requires Angular Language Server to be attached to the current buffer. These functions use Angular-specific server commands and report a notice if the server is unavailable or the buffer is outside an Angular project.

Stylesheet navigation and workspace project discovery do not require Angular Language Server.

## Stylesheet lookup

Stylesheet navigation checks sources in this order:

1. `styleUrl` or `styleUrls` in the component TypeScript file.
2. Conventional sibling `.scss`, `.sass`, `.css`, or `.less` files.
3. For an HTML template without a conventional match, style metadata in its sibling component TypeScript file.

Only existing stylesheet files are offered or opened.
