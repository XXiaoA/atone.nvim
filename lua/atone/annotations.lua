---@meta

---@alias AtoneWindowDirection "left"|"right"
---@alias AtoneWindowSize "adaptive"|number
---@alias AtoneKeymap string|string[]
---@alias AtoneNodeLabelChunk [string, string]
---@alias AtoneNodeLabel string|AtoneNodeLabelChunk[]

---@class AtoneNode
---@field seq integer
---@field time integer?
---@field depth integer
---@field parent integer?
---@field children integer[]
---@field child integer?
---@field fork boolean?
---@field label string|table|nil

---@class AtoneNodeLabelContextDiff
---@field added integer
---@field removed integer

---@class AtoneNodeLabelContext
---@field seq integer
---@field is_current boolean
---@field is_sticky_ref boolean Whether this node is the pinned sticky diff reference
---@field time integer
---@field h_time string Time in a human-readable format
---@field bookmark string? Bookmark label text built by `mark.build_labels`
---@field diff AtoneNodeLabelContextDiff Diff statistics

---@class AtoneCharSpan
---@field line integer 1-based line index within the hunk body
---@field col_start integer 0-based column (inclusive)
---@field col_end integer 0-based column (exclusive)

---@class AtoneIntraChanges
---@field add_spans AtoneCharSpan[]
---@field del_spans AtoneCharSpan[]

---@class AtoneChangeGroup
---@field del_lines {idx: integer, text: string}[]
---@field add_lines {idx: integer, text: string}[]

---@class AtoneCmdSubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[]

---@class AtoneLayoutConfig
---@field direction? AtoneWindowDirection
---@field width? AtoneWindowSize

---@class AtoneDiffCurNodeConfig
---@field enabled? boolean
---@field split_percent? number
---@field width? AtoneWindowSize
---@field treesitter? boolean
---@field inline_diff? boolean

---@class AtoneDiffFloatConfig
---@field width? number
---@field height? number
---@field autoclose? boolean

---@class AtoneAutoAttachConfig
---@field enabled? boolean
---@field excluded_ft? string[]

---@class AtoneMarksConfig
---@field persist? boolean
---@field persist_path? string
---@field finders? string[]

---@class AtoneTreeKeymapsConfig
---@field quit? AtoneKeymap
---@field next_node? AtoneKeymap
---@field pre_node? AtoneKeymap
---@field jump_to_G? AtoneKeymap
---@field jump_to_gg? AtoneKeymap
---@field undo_to? AtoneKeymap
---@field set_mark? AtoneKeymap
---@field delete_mark? AtoneKeymap
---@field delete_all_marks? AtoneKeymap
---@field goto_mark? AtoneKeymap
---@field mark_picker? AtoneKeymap
---@field help? AtoneKeymap
---@field undo? AtoneKeymap
---@field redo? AtoneKeymap
---@field float_diff? AtoneKeymap

---@class AtoneAutoDiffKeymapsConfig
---@field quit? AtoneKeymap
---@field help? AtoneKeymap
---@field undo? AtoneKeymap
---@field redo? AtoneKeymap
---@field float_diff? AtoneKeymap

---@class AtoneHelpKeymapsConfig
---@field quit_help? AtoneKeymap

---@class AtoneKeymapsConfig
---@field tree? AtoneTreeKeymapsConfig
---@field auto_diff? AtoneAutoDiffKeymapsConfig
---@field help? AtoneHelpKeymapsConfig

---@class AtoneNodeLabelConfig
---@field custom? boolean
---@field formatter? fun(ctx: AtoneNodeLabelContext): AtoneNodeLabel
---@field extmark_opts? vim.api.keyset.set_extmark

---@class AtoneGraphSymbols
---@field node string
---@field vline string
---@field hline string
---@field fork string
---@field merge string
---@field corner string
---@field node_glyphs? table<integer, string>

---@class AtoneUIConfig
---@field border? string
---@field compact? boolean
---@field branch_symbols? boolean|"auto"
---@field node_label? AtoneNodeLabelConfig

---@class AtoneConfig
---@field layout? AtoneLayoutConfig
---@field diff_cur_node? AtoneDiffCurNodeConfig
---@field diff_float? AtoneDiffFloatConfig
---@field auto_attach? AtoneAutoAttachConfig
---@field marks? AtoneMarksConfig
---@field keymaps? AtoneKeymapsConfig
---@field ui? AtoneUIConfig

return {}
