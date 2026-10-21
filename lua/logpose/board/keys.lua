--- The board's key mappings and help text.
local taskfile = require("logpose.taskfile")
local ui = require("logpose.util.ui")
local view = require("logpose.board.view")
local history = require("logpose.board.history")
local actions = require("logpose.board.actions")

local M = {}

M.HELP = {
  "logpose board",
  "  h / l        previous / next column      j / k   previous / next card",
  "  H / L  < >   move the card left / right  1-9     move it to column N",
  "  x            done                        b       block / unblock",
  "  <C-j>/<C-k>  move the card down / up     a       add a card here",
  "  K            peek: the task in a float   D       delete the card (asks)",
  "  n            notes linked with the task (meetings, daily notes …)",
  "  N            make a note from the task's write-up (copy or move it)",
  "  <CR>         open the task file          /       filter (find filters)",
  "  z            fold / unfold the column    gg / G  first / last card",
  "  u / <C-r>    undo / redo a board change",
  "  c            compact cards on / off      s       rows per project on / off",
  "  p            this project / all          P       projects (switch)",
  "  m            move the card to a project  e       edit the card's fields",
  "  v            mark / unmark the card      V <Esc> unmark all",
  "               (H L 1-9 x b m e then act on every marked card)",
  "  r            refresh                     q       close",
  "  ?            this help",
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
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, ui.safely(fn), { buffer = b.buf, nowait = true, silent = true, desc = desc })
  end
  local function step(dc, dr)
    return function()
      b.focus.col = b.focus.col + dc
      b.focus.row = b.focus.row + dr
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
      actions.move(b, -1)
    end, "Move card left")
  end
  for _, lhs in ipairs({ "L", ">" }) do
    map(lhs, function()
      actions.move(b, 1)
    end, "Move card right")
  end
  for i = 1, math.min(9, #taskfile.columns()) do
    map(tostring(i), function()
      actions.move_to(b, i)
    end, "Move card to column " .. i)
  end
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
    require("logpose.util.ui").notify(table.concat(M.HELP, "\n"), vim.log.levels.INFO)
  end, "Help")
end

return M
