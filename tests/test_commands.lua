local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = { pre_case = child.setup, post_once = child.stop },
})

local function register_dummy()
  child.lua([[
    local commands = require("logpose.commands")
    commands.subcommands = {}
    commands.register("daily", {
      impl = function(opts) _G.called = opts end,
      complete = function() return { "today", "prev", "next" } end,
    })
    commands.register("archive", { impl = function() error("logpose: boom", 0) end })
    commands.register("grep", { impl = function() error("plain failure", 0) end })
  ]])
end

T[":Logpose exists"] = function()
  eq(child.fn.exists(":Logpose"), 2)
end

T["without a subcommand prints usage"] = function()
  child.cmd("Logpose")
  H.contains(
    child.notifications()[1].msg,
    "usage :Logpose {actions|archive|capture|daily|done|find|grep|init|meeting|project}"
  )
end

T["built-in subcommands are registered"] = function()
  eq(
    child.fn.getcompletion("Logpose ", "cmdline"),
    { "actions", "archive", "capture", "daily", "done", "find", "grep", "init", "meeting", "project" }
  )
  H.neq(child.fn.maparg("<Plug>(logpose-meeting)", "n"), "")
end

T["completion"] = MiniTest.new_set()

T["completion"]["lists subcommands"] = function()
  register_dummy()
  eq(child.fn.getcompletion("Logpose ", "cmdline"), { "archive", "daily", "grep" })
  eq(child.fn.getcompletion("Logpose da", "cmdline"), { "daily" })
end

T["completion"]["delegates to the subcommand"] = function()
  register_dummy()
  eq(child.fn.getcompletion("Logpose daily ", "cmdline"), { "today", "prev", "next" })
  eq(child.fn.getcompletion("Logpose daily p", "cmdline"), { "prev" })
  eq(child.fn.getcompletion("Logpose archive ", "cmdline"), {})
end

T["dispatch"] = MiniTest.new_set()

T["dispatch"]["passes args, bang and range"] = function()
  register_dummy()
  child.cmd("Logpose! daily prev extra")
  local called = child.lua_get("_G.called")
  eq(called.args, { "prev", "extra" })
  eq(called.bang, true)
  eq(called.range, 0)
end

T["dispatch"]["accepts a trailing ! on the subcommand"] = function()
  register_dummy()
  child.cmd("Logpose daily! prev")
  eq(child.lua_get("_G.called.bang"), true)
  eq(child.lua_get("_G.called.args"), { "prev" })
end

T["dispatch"]["reports unknown subcommands with the valid ones"] = function()
  register_dummy()
  child.cmd("Logpose nope")
  local note = child.notifications()[1]
  H.contains(note.msg, 'unknown subcommand "nope"')
  H.contains(note.msg, "archive, daily, grep")
  eq(note.level, child.lua_get("vim.log.levels.ERROR"))
end

T["dispatch"]["turns errors into notifications"] = function()
  register_dummy()
  child.cmd("Logpose archive")
  child.cmd("Logpose grep")
  local notes = child.notifications()
  eq(notes[1].msg, "logpose: boom")
  eq(notes[2].msg, "logpose: plain failure")
end

T["registers <Plug> mappings"] = function()
  register_dummy()
  H.neq(child.fn.maparg("<Plug>(logpose-daily)", "n"), "")
  child.api.nvim_feedkeys(child.api.nvim_replace_termcodes("<Plug>(logpose-daily)", true, false, true), "x", false)
  eq(child.lua_get("_G.called.args"), {})
end

return T
