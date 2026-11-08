local MiniTest = require('mini.test')
-- Reopening the last session, against a real engine.

local eq = MiniTest.expect.equality
local helpers = dofile('tests/helpers.lua')
local state = require('sqmeow.core.state')
local drawer = require('sqmeow.ui.drawer')
local file = require('sqmeow.sources.file')

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      require('sqmeow').setup({
        core = { path = vim.fn.tempname() },
        ui = { persist_session = true },
      })
      package.loaded['sqmeow.session'] = nil
    end,
    post_case = function()
      for _, connection in ipairs(state.connection_list()) do
        require('sqmeow.api.connection').disconnect(connection.id)
      end
      helpers.wait_for('every connection should close', function()
        return next(state.connections) == nil
      end)
      require('sqmeow').setup({})
    end,
  },
})

T['reopens the saved connections, the current one, and the open drawer nodes'] = function()
  file.add({ name = 'kept', url = 'sqlite::memory:' })
  file.add({ name = 'other', url = 'sqlite::memory:' })
  local kept = helpers.connect('sqlite::memory:', { name = 'kept' })
  local other = helpers.connect('sqlite::memory:', { name = 'other' })
  -- Opened by URL rather than from a source, so it has nothing to be opened again from.
  helpers.connect('sqlite::memory:', { name = 'loose' })
  require('sqmeow.api.connection').use(other)
  drawer.expand(other, {})
  require('sqmeow.server.session').save()

  for _, id in ipairs({ kept, other, state.connection_by_name('loose').id }) do
    require('sqmeow.api.connection').disconnect(id)
  end
  helpers.wait_for('every connection should close', function()
    return next(state.connections) == nil
  end)

  package.loaded['sqmeow.session'] = nil
  require('sqmeow.server.session').restore()
  helpers.wait_for('the saved connections should reopen', function()
    local first, second = state.connection_by_name('kept'), state.connection_by_name('other')
    return first ~= nil
      and second ~= nil
      and first.state == 'connected'
      and second.state == 'connected'
  end)
  eq(state.connection_by_name('loose'), nil)
  eq(state.current_connection().name, 'other')
  eq(drawer.is_expanded(state.connection_by_name('other').id, {}), true)
end

T['reopens the connection folders it saved'] = function()
  file.add({ name = 'kept', url = 'sqlite::memory:', group = 'work' })
  helpers.connect('sqlite::memory:', { name = 'kept', group = 'work' })
  drawer.reopen_groups({ 'work' })
  require('sqmeow.server.session').save()

  -- A fresh drawer forgets everything, the way a restart does.
  drawer.reset()
  eq(drawer.open_groups(), {})

  -- The module restores once per copy, so a second restore needs a fresh one.
  package.loaded['sqmeow.server.session'] = nil
  require('sqmeow.server.session').restore()
  eq(drawer.open_groups(), { 'work' })
  eq(state.connection_by_name('kept').group, 'work')
end

return T
