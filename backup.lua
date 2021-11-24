#!/usr/local/bin/lua
--[[    backup.lua

Save and restore changes in text files.
See "usage" for details.

2020-2021, Stanislav Mikhel ]]

-- output extention
EXT = ".bkp"      

-- help
local usage = [[
USAGE: %s [file] cmd [option] [branch]

  Commands:
    add  [msg] [br] - save changes in file
    rev  [n]   [br] - create n-th revision of the file
    diff [n]   [br] - comapre file with n-th revision
    log        [br] - show all commits
    vs   file2      - compare two files
    base  n    [br] - update initial commit
    pop        [br] - remove last commit
    summ       [br] - short summary
    rm         [br] - remove file history

]]

-- functions
local strfind   = string.find
local strmatch  = string.match
local strsub    = string.sub
local strformat = string.format

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
    ab = ab+1
  end
  -- skip end
  while ab <= an and ab <= bn and a[an] == b[bn] do
    an, bn = an-1, bn-1
  end  
  -- make table
  local S, ab1 = {}, ab-1
  S[ab1] = setmetatable({}, {__index=function() return ab1 end}) 
  for i = ab, an do
    S[i] = {[ab1]=ab1}
    local Si,Si1, ai = S[i],S[i-1],a[i]
    for j = ab, bn do
      Si[j] = (ai==b[j]) and (Si1[j-1]+1) 
                          or math.max(Si[j-1], Si1[j]) 
    end
  end
  local Ncom = S[an][bn]   -- total number of common strings  
  -- prepare table
  local common = {}
  --for i = 0,N do 
  for i = 0, (Ncom + #a - an) do
    common[i] = (i < ab) and {i,i} or 0
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
      an, bn, N = an-1, bn-1, N-1
    end
  end
  an, bn = #a+1, #b+1
  for i = #common+1, Ncom+1, -1 do    
    common[i] = {an,bn}
    an, bn = an-1, bn-1
  end
  return common 
end

-- show difference
diff.print = function (a, b)
  local common = diff.lcs(a, b)
  --for i = 1,#common do print(common[i][1],a[common[i][1]]) end
  local tbl, sign = {a, b}, {"-- ", "++ "}
  for n = 1, #common do
    for k = 1,2 do
      local n1, n2 = common[n-1][k]+1, common[n][k]-1
      if n2 >= n1 then
        io.write("@@ ", n1, "..", n2, "\n")
        for i = n1, n2 do io.write(sign[k], tbl[k][i], "\n") end
      end
    end
  end
end

-- make single-linked list
local function addString (s, parent)
  parent.child = {s, child=parent.child}
  return parent.child
end

-- move forward along the list
local function goTo (node, iCur, iGoal)
  for i = iCur+1, iGoal do node = node.child end
  return node, iGoal
end

-- list to table
local function toTbl (ptr)
  local t = {}
  while ptr do
    t[#t+1] = ptr[1]
    ptr = ptr.child
  end
  return t
end

-- file mapping
local filemap = {}

-- prepare backup file name
local function bkpname(fname,br)
  local map = filemap[fname]
  fname = map and map or fname
  return fname..(br and ('.'..br) or '')..EXT
end

-- parse command line arguments
local argparse = {}

-- add msg branch | add msg | add
argparse.add = function (a)
  return bkpname(a[1],a[4]), a[3], a[4]
end

-- log branch | log
argparse.log = function (a)
  return bkpname(a[1],a[3]), nil, a[3]
end

-- summ branch | summ
argparse.summ = argparse.log

-- rev n branch | rev n | rev branch | rev
argparse.rev = function (a)
  local n = tonumber(a[3]) 
  if a[4] then 
    return bkpname(a[1],a[4]), n, a[4]
  end
  if n then
    return bkpname(a[1],nil), n, nil
  else
    return bkpname(a[1],a[3]), nil, a[3]
  end
end

-- diff n branch | diff n | diff branch | diff
argparse.diff = argparse.rev

-- base n branch | base n
argparse.base = function(a)
  return bkpname(a[1],a[4]), tonumber(a[3]), a[4]
end

-- pop branch | pop
argparse.pop = argparse.log

-- rm branch | rm
argparse.rm = argparse.log

-- return backup name, parameter, branch
argparse._get_ = function (a)
  return argparse[ a[2] ](a)
end

-- available commands
local command = {}

-- collect commit lines
command._commits_ = function (fname)
  local ok, res = pcall(function ()
    local list = {}
    for line in io.lines(fname) do
      if strfind(line, "^BKP NEW ") then
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
    print(strsub(v, 9))
  end
end

-- prepare file version based on bkp file
command._make_ = function (fname, last) 
  -- update revision
  if last and last <= 0 then
      -- search in backward direction
      local tmp = command._commits_(fname)
      local v = strmatch(tmp[#tmp + last] or "", "^BKP NEW (%d+) : .*")
      last = tonumber(v)  -- get last commit if out of range
  end
  local f = io.open(fname, 'r') 
  if f == nil then return {}, 0 end
  -- continue if the file found
  local begin, rev = {}
  local curr, index, id, del = nil, 0, 0, true
  for line in f:lines() do
    if #line > 8 and strfind(line, "^BKP ") then 
      -- execute command
      local cmd, v1, v2 = strmatch(line, "^BKP (%u%u%u) (%d+) : (.*)")
      v1 = tonumber(v1)
      if cmd == "NEW" then                            -- commit
        if v1-1 == last then break 
        else 
          curr, index, id, del = begin, 0, v1, true   -- reset all
        end
        rev = strsub(line, 9)
      elseif cmd == "ADD" then                        -- insert lines
        if del then
          curr, index, del = begin, 0, false          -- reset, change flag
        end
        curr, index = goTo(curr, index, v1-1)
      elseif cmd == "REM" then                        -- remove lines
        curr, index = goTo(curr, index, v1-1)  
        local curr2, index2 = goTo(curr, index, v1+tonumber(v2))
        curr.child, index = curr2, index2 - 1         -- update indexation
      end
    else
      -- insert line
      curr = addString(line, curr)             
      index = index + 1
    end
  end
  f:close()
  return toTbl(begin.child), id, rev
end

-- "commit"
command.add = function (a)
  local fname, msg, br = argparse._get_(a)
  local saved, id = command._make_(fname) 
  local new = diff.read(a[1])
  local common = diff.lcs(saved, new) 
  if #saved == #new and #new == #common-1 then return end
  -- save commit
  local f = io.open(fname, "a")
  f:write(strformat("BKP NEW %d : %s\n", id+1, msg or ''))
  -- remove old lines
  if #saved > #common-1 then
    for n = 1, #common do
      local n1, n2 = common[n-1][1]+1, common[n][1]
      if n2 > n1 then
        f:write(strformat("BKP REM %d : %d\n", n1, n2-n1))
      end
    end
  end
  -- add new lines
  if #new > #common-1 then
    for n = 1, #common do
      local n1, n2 = common[n-1][2]+1, common[n][2]
      if n2 > n1 then
        f:write(strformat("BKP ADD %d : %d\n", n1, n2-n1))
        for i = n1, n2-1 do f:write(new[i],'\n') end
      end
    end
  end
  print(strformat("Save [%s%d] %s", (br and br..' ' or ''), id+1, msg or ''))
end

-- restore the desired file version
command.rev = function (a)
  local fname, ver = argparse._get_(a)
  local saved, id, msg = command._make_(fname, ver) 
  if id == 0 then return print("No commits") end
  -- save result
  io.open(a[1], "w"):write(table.concat(saved, '\n'))
  io.write("Revision ", msg, "\n")
end

-- difference between the file and some revision
command.diff = function (a)
  local fname, ver = argparse._get_(a)
  local saved, id, msg = command._make_(fname, ver) 
  if id == 0 then return print("No commits", ver) end
  -- compare
  io.write("Revision ", msg, "\n")
  diff.print(saved, diff.read(a[1]))
end

-- comare two files 
command.vs = function (a)
  local fname1, fname2 = a[1], a[3]
  if not fname2 then return command.wtf('?!') end
  diff.print(diff.read(fname1), diff.read(fname2))
end

-- update initial version
command.base = function (a)
  local fname,ver = argparse._get_(a) 
  local tbl = diff.read(fname) 
  local ind, comment = 0, '^BKP NEW '..(a[3] or 'None')
  for i = 1,#tbl do 
    if strfind(tbl[i],comment) then 
      io.write('Delete before "', strsub(tbl[i],9), '"\nContinue (y/n)? ')
      if 'y' == io.read() then ind = i end
      break
    end
  end
  if ind == 0 then return end
  -- save previous changes
  local f = io.open(fname:gsub(EXT..'$',".v"..a[3]..EXT),"w")
  for i = 1,ind-1 do f:write(tbl[i],'\n') end
  f:close() 
  -- save current version
  local saved,id = command._make_(fname,ver)
  f = io.open(fname,'w') 
  f:write(strformat("BKP NEW %d : Update base\nBKP ADD 1 : %d\n",ver,#saved))
  for i = 1,#saved do f:write(saved[i],'\n') end
  -- start from the next commit
  ind = ind+1
  while ind <= #tbl and not strfind(tbl[ind],"^BKP NEW ") do ind = ind+1 end 
  for j = ind,#tbl do f:write(tbl[j],'\n') end 
  f:close()
end

-- remove last revision
command.pop = function (a)
  local fname = argparse._get_(a)
  local tbl = diff.read(fname)
  local line
  repeat 
    line = table.remove(tbl)
  until strfind(line, "^BKP NEW ")
  if #tbl == 0 then
    os.remove(fname)
  else
    local f = io.open(fname, 'w')
    f:write(table.concat(tbl, '\n')); f:write('\n')
    f:close()
  end
  print("Remove", strsub(line, 9))
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
      if strfind(line, "^BKP NEW ") then
        total = total + 1
        last = strsub(line, 9)
      end
    end
    print(strformat("size: %.1f kB | commits: %d | last: %s", (len / 1024), total, last))
  end)
  if not v then print("commits: 0") end 
end

-- call unexpected argument
setmetatable(command, {__index=function() 
  print(strformat(usage, arg[0])) 
  return function() end
end})

-- don't call for file group
local individual = {
  vs=true,   -- require two file names
  -- comment to make available
  log=true,  -- can be too long
  base=true, -- require confirm for each file
}

-- mapping 'file > path'
local function update(files,dir)
  if files then
    local sep = strsub(package.config, 1, 1)  -- system-dependent separator
    dir = DIR and DIR..sep or ""
    local name = {}
    -- single files
    for _,v in ipairs(files) do
      name[v] = true
      filemap[v] = dir..v
    end
    -- explicit definitions
    for k,v in pairs(files) do
      if not name[v] then
        filemap[k] = dir..v
      end
    end
  end
end

-- execute operation
backup = function ()
  update(FILES, DIR)
  if individual[ arg[1] ] then
    -- not "defined"
    print(strformat("Choose file for '%s':\n", arg[1]))
    for src in pairs(filemap) do print(src) end
  elseif argparse[ arg[1] ] then 
     -- valid group command
    local a = {0, arg[1], arg[2], arg[3]}
    for src in pairs(filemap) do
      a[1] = src
      print(strformat("\t%s:", src))
      command[ a[2] ](a)
    end
  else
    -- process command for single file
    command[ arg[2] ](arg)
  end
end

-- for further use
return {
  diff = diff, 
  command = command,
}
