# backup

**Lua** based library for the local version control of text files. The information is stored in _bkp_ files in the same directory where the original files are located. CLI is used to switch between different revisions and do other operations with the file versions.

## Usage

Put into your project directory a **Lua** file with the following minimal content:

```lua
require "backup"
backup()
```
Make it executable for convenience. If the file name, for example, is _vc.lua_, then the program can be called as follows

```
./vc.lua [file] command [option] [branch]
```

Commands and options: 
- **add** _(msg)_ _(branch)_ - save last changes in file
- **rev** _(n)_ _(branch)_ - switch to the n-th revision of the file
- **remv** _(msg)_ _(branch)_ - switch to revision with the given comment message
- **diff** _(n)_ _(branch)_ - compare current state with the n-th revision
- **log** _(branch)_ - show all commits
- **summ** _(branch)_ - short summary
- **merge** _branch_ - merge file from other branch, require to resolve conflicts and save the result
- **base** _(n)_ _(branch)_ - update initial commit
- **pop** _(branch)_ - remove last commit
- **rm** _(branch)_ - clear file history

Default value for _n_ is the last revision, negative values can be used for backward search, default _branch_ or _msg_ name is empty string.

## File group

If the project conatains more than one file, it is useful to create talbe _FILES_ with the file list In this case the command option _file_ can be skipped. Variable _EXT_ can be used to change the backup file extention.
In other to store all the backups into the same single directory, set its name into the _DIR_ variable (the directory must exist). If _DIR_ is defined, each files in subdirectories must be matched with short names using key-value notation.
Only part of operations with the group of files is available, but manipulations with individual files still can be done. 

### Example 

Assume that we want to work with group of files and store _bkp_ in the _foo_ directory. The following three versions of configuratino file are equal. 
```lua
#!/usr/local/lib/lua
require 'backup'

--    1st version
FILES = {
["file1"] = "foo/file1",
["file2"] = "foo/file2",
["path/to/file3"] = "foo/file3",
}

--    2nd version
DIR = "foo"
FILES = {
["file1"] = "file1",
["file2"] = "file2",
["path/to/file3"] = "file3",
}

--    3rd version
DIR = "foo"
FILES = {
"file1",
"file2",
}
FILES["path/to/file3"] = "file3"

backup()
```
