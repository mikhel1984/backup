#!/usr/local/bin/lua
--[[    backup.lua

Save and restore changes in text files.
See "usage" for details.

2020-2025, Stanislav Mikhel ]]

-- GLOBAL VARIABLES
EXT = "bkp"      -- output extention
BRANCH = nil     -- default branch
DIR = nil        -- backup directory
FILES = nil      -- file list
MERGEREM = false -- show lines that have been removed
COLOR = nil      -- highlight text messages

-- help
local usage = [[
USAGE: %s [file] cmd [option] [branch]

  Commands:
    add  [msg] [br] - save changes in file
    rev  [n]   [br] - switch to the n-th revision
    revm [msg] [br] - switch to revision with comment message or date
    diff [n]   [br] - comapre file with n-th revision
    log        [br] - show all commits
    summ       [br] - short summary
    merge       br  - merge the branch
    base  n    [br] - update initial commit
    pop        [br] - remove last commit
    rm         [br] - clear file history
    pack [nm]  [br] - save files to archive
    unpack          - extract files from archive
]]

-- functions
local sfind   = string.find
local smatch  = string.match
local sgmatch = string.gmatch
local ssub    = string.sub
local sformat = string.format

-- ansi color codes
local text = {
  RED = '\x1b[31m',
  GREEN = '\x1b[32m',
  BOLD = '\x1b[1m',
  END = '\x1b[0m',
}

-- show colored text
text._show_ = function (clr, ...)
  if COLOR then io.write(clr) end
  io.write(...)
  if COLOR then io.write(text.END) end
end

-- simplify call
text.showRed   = function(...) return text._show_(text.RED, ...) end
text.showGreen = function(...) return text._show_(text.GREEN, ...) end
text.showBold  = function(...) return text._show_(text.BOLD, ...) end

-- time stamp
text.now = function () return os.date('[%Y/%m/%d %H:%M] ') end

-- file name time stamp
text.nowFile = function () return os.date('%Y-%m-%d_%H-%M') end

-- file separator
text.sep = ssub(package.config, 1, 1)


-- file comparison
local diff = {}

-- Convert text file into the table of strings
diff.read = function (fname)
  local t = {}
  for line in io.lines(fname) do t[#t+1] = line end
  return t
end

-- Find longest common subgroup
diff.lcs = function (a, b)
  local an, bn, ab = #a, #b, 1
  -- skip begin
  while ab <= an and ab <= bn and a[ab] == b[ab] do
    ab = ab + 1
  end
  -- skip end
  while ab <= an and ab <= bn and a[an] == b[bn] do
    an, bn = an - 1, bn - 1
  end
  -- make table
  local S, ab1, mmax = {}, ab - 1, math.max
  S[ab1] = setmetatable({}, {__index=function() return ab1 end})
  for i = ab, an do
    S[i] = {[ab1]=ab1}
    local Si, Si1, ai = S[i], S[i-1], a[i]
    for j = ab, bn do
      Si[j] = (ai == b[j])
              and (Si1[j-1] + 1)
              or mmax(Si[j-1], Si1[j])
    end
  end
  local Ncom = S[an][bn]   -- total number of common strings
  -- prepare table
  local common = {}
  --for i = 0,N do
  for i = 0, (Ncom + #a - an) do
    common[i] = (i < ab) and {i, i} or 0
  end
  -- collect
  local N = Ncom
  while N > ab1 do
    local Sab = S[an][bn]
    if Sab == S[an-1][bn] then
      an = an - 1
    elseif Sab == S[an][bn-1] then
      bn = bn - 1
    else
      --assert (a[an] == b[bn])
      common[N] = {an, bn}
      an, bn, N = an - 1, bn - 1, N - 1
    end
  end
  an, bn = #a + 1, #b + 1
  for i = #common+1, Ncom+1, -1 do
    common[i] = {an, bn}
    an, bn = an - 1, bn - 1
  end
  return common
end

-- show difference
diff.print = function (a, b)
  local common = diff.lcs(a, b)
  local tbl, sign, clr = {a, b}, {"-- ", "++ "}, {text.showRed, text.showGreen}
  for n = 1, #common do
    for k = 1, 2 do
      local n1, n2 = common[n-1][k] + 1, common[n][k] - 1
      if n2 >= n1 then
        io.write("@@ ", n1, "..", n2, "\n")
        for i = n1, n2 do clr[k](sign[k], tbl[k][i], "\n") end
      end
    end
  end
end

-- transform a to b, save result to file
diff.merge = function (f, a, b, msg)
  local common = diff.lcs(a, b)
  local p1, p2 = table.unpack(common[0])
  local _OLD_, _MID_, _NEW_ = '<<<<<<<<\n', '========\n', '>>>>>>>> '
  local conflicts = false
  for n = 1, #common do
    local c1, c2 = table.unpack(common[n])
    if c2-1 > p2 then
      if c1-1 > p1 then
        -- have to resolve conflict
        conflicts = true
        f:write(_OLD_)
        for i = p1+1, c1-1 do f:write(a[i], '\n') end -- old
        f:write(_MID_)
        for i = p2+1, c2-1 do f:write(b[i], '\n') end -- new
        f:write(_NEW_, msg or '', '\n')
      else
        -- simple add new lines
        for i = p2+1, c2-1 do f:write(b[i], '\n') end
      end
    elseif c1-1 > p1 and MERGEREM then
      -- removed lines
      f:write(_OLD_)
      for i = p1+1, c1-1 do f:write(a[i], '\n') end -- old
      f:write(_MID_)
      f:write(_NEW_, msg or '', '\n')
    end
    if b[c2] then f:write(b[c2], '\n') end
    p1, p2 = c1, c2
  end
  if conflicts then print("Reslove the conflicts!") end
end

-- make single-linked list
local function _addString (s, parent)
  parent.child = {s, child=parent.child}
  return parent.child
end

-- move forward along the list
local function _goTo (node, iCur, iGoal)
  for i = iCur+1, iGoal do node = node.child end
  return node, iGoal
end

-- list to table
local function _toTbl (ptr)
  local t = {}
  while ptr do
    t[#t+1] = ptr[1]
    ptr = ptr.child
  end
  return t
end

-- file mapping
local _filemap = {}

-- path/to/file -> path-S-to-S-file
local function _longToSingle (fname)
  local templ = (text.sep == '/') and '/' or '\\'
  return string.gsub(fname, templ, '-S-')
end

-- prepare backup file name
local function _bkpname(fname, br)
  local map = _filemap[fname]
  if not map then
    local dir = DIR and DIR..(text.sep) or ""
    map = dir .. _longToSingle(fname)
  end
  return sformat("%s%s.%s", map, br and ('.'..br) or '', EXT)
end


-- parse command line arguments
local argparse = {}

-- add msg branch | add msg | add
argparse.add = function (a)
  local br = a[4] or BRANCH
  local msg = text.now() .. (a[3] or '')
  return _bkpname(a[1], br), msg, br
end

-- log branch | log
argparse.log = function (a)
  local br = a[3] or BRANCH
  return _bkpname(a[1], br), nil, br
end

-- summ branch | summ
argparse.summ = argparse.log

-- rev n branch | rev n | rev branch | rev
argparse.rev = function (a)
  local n = tonumber(a[3])
  local br = a[4] or BRANCH
  if br or n then
    return _bkpname(a[1], br), n, br
  end
  br = a[3] or BRANCH
  return _bkpname(a[1], br), nil, br
end

-- revm msg branch | revm msg | revm
argparse.revm = function (a)
  local br = a[4] or BRANCH
  return _bkpname(a[1], br), a[3], br
end

-- diff n branch | diff n | diff branch | diff
argparse.diff = argparse.rev

-- merge branch
argparse.merge = function (a)
  local br = a[3] or BRANCH
  return a[1], _bkpname(a[1], br), br
end

-- base n branch | base n
argparse.base = function (a)
  local br = a[4] or BRANCH
  return _bkpname(a[1], br), tonumber(a[3]), br
end

-- pop branch | pop
argparse.pop = argparse.log

-- rm branch | rm
argparse.rm = argparse.log

-- pack name branch | pack name | pack
argparse.pack = argparse.revm

-- unpack
argparse.unpack = function (a)
  return a[1]
end

-- return backup name, parameter, branch
argparse._get_ = function (a)
  return argparse[ a[2] ](a)
end


local _onlyChanged = true
-- compression state
local _dict, _compressed, _i_next, _w = {}, {}, 0, ''


-- available commands
local command = {}

-- collect commit lines
command._commits_ = function (fname)
  local ok, res = pcall( function ()
    local list = {}
    for line in io.lines(fname) do
      if sfind(line, "^BKP NEW ") then
        list[#list+1] = line
      end
    end
    return list
  end)
  return ok and res or {}
end

-- show commits
command.log = function (a)
  local fname = argparse._get_(a)
  for _, v in ipairs(command._commits_(fname)) do
    print(ssub(v, 9))
  end
end

-- prepare file version based on bkp file
command._make_ = function (fname, last)
  -- update revision
  if last and last <= 0 then
      -- search in backward direction
      local tmp = command._commits_(fname)
      local v = smatch(tmp[#tmp + last] or "", "^BKP NEW (%d+) : .*")
      last = tonumber(v)  -- get last commit if out of range
  end
  local f = io.open(fname, 'r')
  if f == nil then
    return {}, 0
  end
  -- continue if the file found
  local begin, rev = {}
  local curr, index, id, del = nil, 0, 0, true
  for line in f:lines() do
    if #line > 8 and sfind(line, "^BKP ") then
      -- execute command
      local cmd, v1, v2 = smatch(line, "^BKP (%u%u%u) (%d+) : (.*)")
      v1 = tonumber(v1)
      if cmd == "NEW" then                            -- commit
        if v1-1 == last then break
        else
          curr, index, id, del = begin, 0, v1, true   -- reset all
        end
        rev = ssub(line, 9)
      elseif cmd == "ADD" then                        -- insert lines
        if del then
          curr, index, del = begin, 0, false          -- reset, change flag
        end
        curr, index = _goTo(curr, index, v1-1)
      elseif cmd == "REM" then                        -- remove lines
        curr, index = _goTo(curr, index, v1-1)
        local curr2, index2 = _goTo(curr, index, v1+tonumber(v2))
        curr.child, index = curr2, index2 - 1         -- update indexation
      end
    else
      -- insert line
      curr = _addString(line, curr)
      index = index + 1
    end
  end
  f:close()
  return _toTbl(begin.child), id, rev
end

-- "commit"
command.add = function (a)
  local fname, msg, br = argparse._get_(a)
  local saved, id = command._make_(fname)
  local new = diff.read(a[1])
  local common = diff.lcs(saved, new)
  if _onlyChanged and #saved == #new and #new == #common-1 then
    return
  end
  -- save commit
  local f = io.open(fname, "a")
  f:write(sformat("BKP NEW %d : %s\n", id+1, msg or ''))
  -- remove old lines
  if #saved > #common-1 then
    for n = 1, #common do
      local n1, n2 = common[n-1][1] + 1, common[n][1]
      if n2 > n1 then
        f:write(sformat("BKP REM %d : %d\n", n1, n2-n1))
      end
    end
  end
  -- add new lines
  if #new > #common-1 then
    for n = 1, #common do
      local n1, n2 = common[n-1][2] + 1, common[n][2]
      if n2 > n1 then
        f:write(sformat("BKP ADD %d : %d\n", n1, n2-n1))
        for i = n1, n2-1 do f:write(new[i],'\n') end
      end
    end
  end
  print(sformat("Save [%s%d] %s", (br and br..' ' or ''), id+1, msg or ''))
end

-- restore the desired file version
command.rev = function (a)
  local fname, ver, br = argparse._get_(a)
  local saved, id, msg = command._make_(fname, ver)
  if id == 0 then
    return print("No commits")
  end
  -- save result
  io.open(a[1], "w"):write(table.concat(saved, '\n'))
  br = br and sformat('[%s] ', br) or ''
  io.write("Revision ", br,  msg, "\n")
end

-- restore using comment message
command.revm = function (a)
  local fname, msg, br = argparse._get_(a)
  local tbl = command._commits_(fname)
  local ver = ""
  -- find the last message
  for i = #tbl, 1, -1 do
    if sfind(tbl[i], msg or '') then
      ver = smatch(tbl[i], "^BKP NEW (%d+) : .*")
      break
    end
  end
  -- save result
  local saved, _, msg = command._make_(fname, tonumber(ver))
  io.open(a[1], "w"):write(table.concat(saved, '\n'))
  br = br and sformat('[%s] ', br) or ''
  io.write("Revision ", br, msg, "\n")
end

-- difference between the file and some revision
command.diff = function (a)
  local fname, ver = argparse._get_(a)
  local saved, id, msg = command._make_(fname, ver)
  if id == 0 then
    return print("No commits", ver)
  end
  -- compare
  io.write("Revision ", msg, "\n")
  diff.print(saved, diff.read(a[1]))
end

-- "merge" the branch
command.merge = function (a)
  local main, brname, branch = argparse._get_(a)
  if not branch then
    return command.wtf('?!')
  end
  pcall(function ()
    local tm = diff.read(main)
    local tb = command._make_(brname)
    local f = io.open(main, 'w')
    diff.merge(f, tm, tb, branch)
    f:close()
  end)
end

-- update initial version
command.base = function (a)
  local fname, ver = argparse._get_(a)
  local tbl = diff.read(fname)
  local ind, comment = 0, '^BKP NEW '..(a[3] or 'None')
  for i = 1, #tbl do
    if sfind(tbl[i], comment) then
      io.write('Delete before "', ssub(tbl[i], 9), '"\nContinue (y/n)? ')
      if 'y' == io.read() then ind = i end
      break
    end
  end
  if ind == 0 then
    return
  end
  -- save previous changes
  local f = io.open(fname:gsub(EXT..'$', sformat("v%s.%s", a[3], EXT)), "w")
  for i = 1, ind-1 do f:write(tbl[i], '\n') end
  f:close()
  -- save current version
  local saved, id = command._make_(fname, ver)
  f = io.open(fname, 'w')
  f:write(sformat("BKP NEW %d : Update base\nBKP ADD 1 : %d\n", ver, #saved))
  for i = 1, #saved do f:write(saved[i], '\n') end
  -- start from the next commit
  ind = ind + 1
  while ind <= #tbl and not sfind(tbl[ind], "^BKP NEW ") do ind = ind + 1 end
  for j = ind, #tbl do f:write(tbl[j], '\n') end
  f:close()
end

-- remove last revision
command.pop = function (a)
  local fname = argparse._get_(a)
  local tbl = diff.read(fname)
  local line = nil
  repeat
    line = table.remove(tbl)
  until sfind(line, "^BKP NEW ")
  if #tbl == 0 then
    os.remove(fname)
  else
    local f = io.open(fname, 'w')
    f:write(table.concat(tbl, '\n'), '\n')
    f:close()
  end
  print("Remove", ssub(line, 9))
end

-- remove file history
command.rm = function (a)
  local fname = argparse._get_(a)
  if os.remove(fname) then
    print("Remove", fname)
  end
end

-- short summary
command.summ = function (a)
  local fname = argparse._get_(a)
  local v = pcall(function()
    local len, last, total = 0, "", 0
    for line in io.lines(fname) do
      len = len + #line
      if sfind(line, "^BKP NEW ") then
        total = total + 1
        last = ssub(line, 9)
      end
    end
    print(sformat("size: %.1f kB | commits: %d | last: %s", (len / 1024), total, last))
  end)
  if not v then print("commits: 0") end
end

-- combine and compress backup files
command.pack = function (a)
  if _i_next == 0 then
    -- init dictionary
    for i = 0, 255 do _dict[string.char(i)] = i end
    _i_next = 256
  end
  local fname = argparse._get_(a)
  print('Read', fname)
  local ok, err = pcall(function ()
    local file = io.open(fname, 'r')
    fname = DIR and ssub(fname, #DIR+2) or fname  -- remove directory name
    -- add file separator
    local txt = sformat('%s\nBKP END %s\n', file:read('a'), fname)
    -- pack
    for s in sgmatch(txt, '.') do
      local w_s = _w..s
      if _dict[w_s] then
        _w = w_s
      else
        _compressed[#_compressed+1] = _dict[_w]
        _dict[w_s] = _i_next
        _i_next, _w = _i_next+1, s
      end
    end
    file:close()
  end)
  if not ok then
    _compressed = {}  -- to avoid saving
    print(err)
  end
end

-- extract backup files for archive
command.unpack = function (a)
  -- init dictionary
  for i = 0, 255 do _dict[i] = string.char(i) end
  local fname = argparse._get_(a)
  local ok, err = pcall(function ()
    -- read file
    local file = assert(io.open(fname, 'rb'), 'File not found')
    local n = file:read(3)
    assert(n == 'VCZ', 'Wrong file type')
    local w, decompressed = '', {}
    local bs, up = 1, 256-1
    local fmt = ">I"..tostring(bs)
    n = file:read(bs)
    -- unpack
    while n do
      local c = string.unpack(fmt, n)
      if c == up then
        -- update size
        bs, up = bs+1, (up+1)*256-1
        fmt = ">I"..tostring(bs)
        n = file:read(bs)
        c = string.unpack(fmt, n)
      end
      local entry = _dict[c] or w..ssub(w, 1, 1)
      decompressed[#decompressed+1] = entry
      if #w > 0 then
        _dict[#_dict+1] = w..ssub(entry, 1, 1)
      end
      w, n = entry, file:read(bs)
    end
    file:close()
    -- split and save
    local txt = table.concat(decompressed)
    local a, b, prev = 1, 0, 1
    local dir = DIR and DIR..(text.sep) or ''
    while true do
      a, b = string.find(txt, 'BKP END .-\n', prev)
      if not a then break end
      local out_name = dir .. ssub(txt, a+8, b-1)
      print('Save', out_name)
      local f = assert(io.open(out_name, 'w'), 'Unable to open file')
      f:write(ssub(txt, prev, a-2))  -- remove newline
      f:close()
      prev = b+1
    end
  end)
  if not ok then print(err) end
end

-- save archive to file
local function _packSave (a)
  if #_compressed == 0 then return end
  _compressed[#_compressed+1] = _dict[_w]
  -- save
  local _, nm, br = argparse._get_(a)
  local fname = sformat('%s%s.vcz', nm or text.nowFile(), br and '.'..br or '')
  local output = assert(io.open(fname, 'wb'), 'Unable to open file')
  output:write('VCZ')  -- add marker
  local bs, up = 1, 256-1
  local fmt = ">I"..tostring(bs)
  for _, v in ipairs(_compressed) do
    if v >= up then
      output:write(string.pack(fmt, up))  -- set marker
      bs, up = bs+1, (up+1)*256-1
      fmt = ">I"..tostring(bs)
    end
    output:write(string.pack(fmt, v))
  end
  output:close()
  print('Save to ' .. fname)
end

-- call unexpected argument
setmetatable(command,
{__index=function()
  print(sformat(usage, arg[0]))
  return function() end
end})

-- don't call for file group
local _individual = {
  -- comment to make available
  log=true,  -- can be too long
  base=true, -- require confirm for each file
  unpack=true, -- expected single archive file
}

-- mapping 'file > path'
local function _updateFilemap(files, dir)
  if files then
    dir = DIR and DIR..(text.sep) or ""
    for _, v in ipairs(files) do
      _filemap[v] = dir .. _longToSingle(v)
    end
  end
end

local function template (fname)
  local f = io.open((fname or 'vc')..'.lua', 'w')
  f:write(
[[#!/usr/local/bin/lua
require "backup"

--   file extention
-- EXT = "bkp"
--   branch name
-- BRANCH = "main"
--   show removed lines in source
-- MERGEREM = true
--   highlight messages
-- COLOR = true
--   save to directory
-- DIR = "foo"
--   file list
FILES = {
-- "1.txt",
-- "2.lua",
}

backup()
]])
  f:close()
end

-- execute command
backup = function (a)
  a = a or arg
  _updateFilemap(FILES, DIR)
  if _individual[ a[1] ] then
    -- not "defined"
    if a[1] == 'unpack' then
      print('Choose vcz file')
    else
      print(sformat("Choose file for '%s':\n", a[1]))
      for src in pairs(_filemap) do print(src) end
    end
  elseif argparse[ a[1] ] then
    -- valid group command
    local aa = {0, a[1], a[2], a[3]}
    _onlyChanged = false    -- add all files
    for src in pairs(_filemap) do
      aa[1] = src
      text.showBold(sformat("\t%s:", src), '\n')
      command[ aa[2] ](aa)
    end
    if a[1] == 'pack' and #_compressed > 0 then _packSave(aa) end
  else
    -- process command for single file
    command[ a[2] ](a)
  end
end

-- for further use
return {
  diff=diff,
  command=command,
  template=template,
}
