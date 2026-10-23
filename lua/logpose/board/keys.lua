--- The board's key mappings and help text.
local taskfile = require("logpose.taskfile")
local ui = require("logpose.util.ui")
local view = require("logpose.board.view")
local history = require("logpose.board.history")
local actions = require("logpose.board.actions")

local M = {}

M.HELP = {
  { "Moving around" },
  { "h l  j k", "previous / next column · previous / next card" },
  { "gg  G", "first / last card" },
  { "z", "fold / unfold the column" },
  { "Cards" },
  { "H L  < >", "move the card left / right" },
  { "{N}gm  gm", "move it to column N · pick the column" },
  { "{N}j {N}L…", "a count repeats a move: 3j, 2L" },
  { "x", "done" },
  { "b", "block (asks why) / unblock" },
  { "<C-j> <C-k>", "move the card down / up" },
  { "a", "add a card here" },
  { "D", "delete the card (asks)" },
  { "m", "move the card to another project" },
  { "e", "edit the card's fields" },
  { "v  V <Esc>", "mark / unmark the card · unmark all (H L gm x b m e act on all)" },
  { "u  <C-r>", "undo / redo a board change" },
  { "Reading" },
  { "<CR>", "open the task file" },
  { "K", "peek: the task in a floating window" },
  { "n", "notes linked with the task" },
  { "N", "a note from the task's write-up" },
  { "View" },
  { "/", "filter: the board follows as you type; Tab completes" },
  { "<BS>", "clear the filter" },
  { "p  P", "this project / all · the projects screen" },
  { "c  s", "compact cards · rows per project" },
  { "r  q", "refresh · close" },
}

---@param b logpose.Board
function M.on_cursor(b)
  if b._placing then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local ci, ri = view.at(b, pos[1], pos[2])
  if ci and ri and (ci ~= b.focus.col or ri ~= b.focus.row) then
    b.focus = { col = ci, row = ri }
    view.highlight_focus(b)
  elseif ci and not ri and ci ~= b.focus.col then
    b.focus = { col = ci, row = 1 }
    view.clamp(b)
    view.highlight_focus(b)
  end
end

---@param b logpose.Board
--- Map the board's keys in its buffer.
function M.attach(b)
  local map = ui.mapper(b.buf)
  -- a count repeats a move: 3j, 2l, 2L
  local function step(dc, dr)
    return function()
      local n = vim.v.count1
      b.focus.col = b.focus.col + dc * n
      b.focus.row = b.focus.row + dr * n
      view.clamp(b)
      view.highlight_focus(b)
      view.place_cursor(b)
    end
  end
  map("h", step(-1, 0), "Previous column")
  map("l", step(1, 0), "Next column")
  map("j", step(0, 1), "Next card")
  map("k", step(0, -1), "Previous card")
  map("<Left>", step(-1, 0), "Previous column")
  map("<Right>", step(1, 0), "Next column")
  map("<Down>", step(0, 1), "Next card")
  map("<Up>", step(0, -1), "Previous card")
  for _, lhs in ipairs({ "H", "<" }) do
    map(lhs, function()
      actions.move(b, -vim.v.count1)
    end, "Move card left")
  end
  for _, lhs in ipairs({ "L", ">" }) do
    map(lhs, function()
      actions.move(b, vim.v.count1)
    end, "Move card right")
  end
  -- digits stay counts (3j); {N}gm moves the card to column N, gm alone asks which
  map("gm", function()
    if vim.v.count > 0 then
      return actions.move_to(b, vim.v.count)
    end
    vim.ui.select(taskfile.columns(), {
      prompt = "Move to column",
      format_item = function(c)
        return c.label
      end,
    }, function(c)
      if c then
        actions.move_to(b, taskfile.column_index(c.key))
      end
    end)
  end, "Move card to a column ({N}gm: column N)")
  map("x", function()
    actions.done(b)
  end, "Done")
  map("b", function()
    actions.toggle_block(b)
  end, "Block / unblock")
  map("<C-j>", function()
    actions.reorder(b, 1)
  end, "Move card down")
  map("<C-k>", function()
    actions.reorder(b, -1)
  end, "Move card up")
  map("K", function()
    actions.peek(b)
  end, "Peek at the task")
  map("n", function()
    actions.notes(b)
  end, "Notes linked with the task")
  map("N", function()
    actions.to_note(b)
  end, "Note from the task")
  map("z", function()
    actions.toggle_fold(b)
  end, "Fold / unfold the column")
  map("c", function()
    b.compact = not b.compact
    view.refresh(b, (view.focused(b) or {}).file)
  end, "Compact cards on / off")
  map("s", function()
    b.lanes = not b.lanes
    view.refresh(b, (view.focused(b) or {}).file)
  end, "Rows per project on / off")
  map("gg", function()
    b.focus.row = 1
    view.highlight_focus(b)
    view.place_cursor(b)
  end, "First card")
  map("G", function()
    b.focus.row = #b.columns[b.focus.col].cards
    view.clamp(b)
    view.highlight_focus(b)
    view.place_cursor(b)
  end, "Last card")
  map("a", function()
    actions.add(b)
  end, "Add card")
  map("D", function()
    actions.delete(b)
  end, "Delete card")
  map("u", function()
    history.undo(b)
  end, "Undo the last board change")
  map("<C-r>", function()
    history.redo(b)
  end, "Redo")
  map("<CR>", function()
    actions.open(b)
  end, "Open task")
  map("<2-LeftMouse>", function()
    M.on_cursor(b)
    actions.open(b)
  end, "Open task")
  map("/", function()
    actions.set_filter(b)
  end, "Filter")
  map("p", function()
    b.all = not b.all
    view.refresh(b, (view.focused(b) or {}).file)
  end, "This project / all")
  map("P", function()
    -- the projects screen; the board follows the project you switch to (LogposeProjectChanged)
    actions.count(b, "switch")
    require("logpose.projects").open(b.root)
  end, "Projects (switch)")
  map("e", function()
    actions.edit(b)
  end, "Edit the card's (or marked cards') fields")
  map("v", function()
    actions.toggle_mark(b)
  end, "Mark / unmark the card")
  map("V", function()
    actions.clear_marks(b)
  end, "Unmark all")
  map("<Esc>", function()
    actions.clear_marks(b)
  end, "Unmark all")
  map("m", function()
    actions.move_to_project(b)
  end, "Move the card to a project")
  map("r", function()
    view.refresh(b, (view.focused(b) or {}).file)
  end, "Refresh")
  map("q", function()
    actions.close(b)
  end, "Close")
  map("?", function()
    require("logpose.util.help").with_filters("Board", M.HELP)
  end, "Help")
  map("<BS>", function()
    if b.filter ~= "" then
      b.filter = ""
      view.refresh(b, (view.focused(b) or {}).file)
    end
  end, "Clear the filter")
end

return M
