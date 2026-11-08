local MiniTest = require('mini.test')
local eq = MiniTest.expect.equality
local helpers = require('tests.helpers')
local drawer = require('sqmeow.ui.drawer')
local utils = require('sqmeow.core.utils')

local T = MiniTest.new_set()

--- A quiet drawer: no redraws, and a clean tree between cases.
local function setup()
  helpers.stub(drawer, 'render', function() end)
  drawer.reset()
  MiniTest.finally(function()
    drawer.reset()
  end)
end

--- Capture what the drawer tells the user.
local function notes()
  local seen = {}
  helpers.stub(utils, 'notify', function(message)
    table.insert(seen, message)
  end)
  return seen
end

T['group_rows'] = MiniTest.new_set()

T['group_rows']['sorts folders first and keeps ungrouped rows in order'] = function()
  local grouped = drawer.group_rows({
    { name = 'root' },
    { name = 'prod', group = 'work/prod' },
    { name = 'dev', group = 'work' },
    { name = 'blog', group = 'personal' },
  })

  eq(grouped.order, { 'personal', 'work', 'work/prod' })
  eq(grouped.folders['work'], { { name = 'dev', group = 'work' } })
  eq(grouped.folders['work/prod'], { { name = 'prod', group = 'work/prod' } })
  eq(grouped.roots, { { name = 'root' } })
end

T['group_rows']['normalizes the path it groups by'] = function()
  local grouped = drawer.group_rows({ { name = 'a', group = ' /work//prod/ ' } })

  eq(grouped.order, { 'work/prod' })
end

T['group_rows']['leaves a blank group at the root'] = function()
  local grouped = drawer.group_rows({ { name = 'a', group = '  ' }, { name = 'b' } })

  eq(grouped.order, {})
  eq(#grouped.roots, 2)
end

T['connection_nodes'] = MiniTest.new_set()

T['connection_nodes']['draws folders before the ungrouped connections'] = function()
  setup()
  local nodes = drawer.connection_nodes({
    { name = 'root', id = 1, status = 'connected', connected = true },
    { name = 'dev', group = 'work' },
    { name = 'blog', group = 'personal' },
  })

  eq(nodes[1].id, 'group:personal')
  eq(nodes[2].id, 'group:work')
  eq(nodes[3].id, 'conn:1')
  eq(nodes[3].kind, 'connection')
end

T['connection_nodes']['draws a nested folder inside its parent'] = function()
  setup()
  local nodes = drawer.connection_nodes({
    { name = 'dev', group = 'work' },
    { name = 'prod', group = 'work/prod' },
  })

  local work = nodes[1]
  eq(work.rel, 'work')
  eq(work.note, '2')
  eq(work:get_child_ids(), { 'group:work/prod', 'conn:dev' })
end

T['connection_nodes']['opens a folder on first sight'] = function()
  setup()
  drawer.connection_nodes({ { name = 'dev', group = 'work' } })

  eq(drawer.open_groups(), { 'work' })
end

T['actions'] = MiniTest.new_set()

T['actions']['toggle opens and closes the folder under the cursor'] = function()
  setup()
  drawer.reopen_groups({ 'work' })
  helpers.stub(drawer, 'current_node', function()
    return { kind = 'connection_group', id = 'group:work', rel = 'work' }
  end)

  drawer.actions.toggle()
  eq(drawer.open_groups(), {})
  drawer.actions.toggle()
  eq(drawer.open_groups(), { 'work' })
end

T['actions']['move_group moves a folder and everything under it'] = function()
  setup()
  helpers.stub(drawer, 'connection_rows', function()
    return {
      { name = 'mine', group = 'work' },
      { name = 'theirs', group = 'work/prod' },
    }
  end)
  helpers.stub(require('sqmeow.sources'), 'find', function(_, name)
    return { name = name, source = name == 'mine' and 'file' or 'project' }
  end)
  local edits = {}
  helpers.stub(require('sqmeow.api.connection'), 'edit', function(_, name, changes)
    table.insert(edits, { name = name, group = changes.group })
    return true
  end)
  local seen = notes()

  drawer.move_group('work', 'staging')
  eq(edits, {
    { name = 'mine', group = 'staging' },
    { name = 'theirs', group = 'staging' },
  })
  eq(seen, {})
end

T['actions']['move_group reports the connections it must leave behind'] = function()
  setup()
  helpers.stub(drawer, 'connection_rows', function()
    return { { name = 'theirs', group = 'work' } }
  end)
  helpers.stub(require('sqmeow.sources'), 'find', function()
    return { name = 'theirs', source = 'project' }
  end)
  local seen = notes()

  drawer.move_group('work', 'staging')
  eq(#seen, 1)
  helpers.contains(seen[1], 'theirs')
end

T['actions']['move_group asks for a name'] = function()
  setup()
  local seen = notes()

  drawer.move_group('work', '  ')
  eq(#seen, 1)
  helpers.contains(seen[1], 'needs a name')
end

T['actions']['delete refuses a folder that still holds connections'] = function()
  setup()
  helpers.stub(drawer, 'current_node', function()
    return { kind = 'connection_group', rel = 'work' }
  end)
  helpers.stub(drawer, 'connection_rows', function()
    return { { name = 'a', group = 'work' } }
  end)
  local seen = notes()

  drawer.actions.delete()
  eq(#seen, 1)
  helpers.contains(seen[1], 'still holds 1')
end

T['actions']['add prefills the folder under the cursor'] = function()
  setup()
  local prefix = 'sentinel'
  helpers.stub(require('sqmeow.ui.connection'), 'create', function(p)
    prefix = p
  end)

  helpers.stub(drawer, 'current_node', function()
    return { kind = 'connection_group', rel = 'work/prod' }
  end)
  drawer.actions.add()
  eq(prefix, 'work/prod')

  -- A connection inside a folder prefills its own folder.
  helpers.stub(drawer, 'current_node', function()
    return { kind = 'connection', name = 'dev', conn_id = 1, group = 'work' }
  end)
  drawer.actions.add()
  eq(prefix, 'work')

  -- Nowhere in particular prefills nothing.
  helpers.stub(drawer, 'current_node', function()
    return nil
  end)
  drawer.actions.add()
  eq(prefix, nil)
end

T['reopen_groups marks saved folders open'] = function()
  setup()
  eq(drawer.open_groups(), {})
  drawer.reopen_groups({ 'work', 'personal' })
  eq(drawer.open_groups(), { 'personal', 'work' })
end

return T
