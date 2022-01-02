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
- **revm** _(msg)_ _(branch)_ - switch to revision with the given comment message
- **diff** _(n)_ _(branch)_ - compare current state with the n-th revision
- **log** _(branch)_ - show all commits
- **summ** _(branch)_ - short summary
- **merge** _branch_ - merge file from other branch, require to resolve conflicts and save the result
- **base** _(n)_ _(branch)_ - update initial commit
- **pop** _(branch)_ - remove last commit
- **rm** _(branch)_ - clear file history

Default value for _n_ is the last revision, negative values can be used for backward search, default _branch_ or _msg_ name is empty string.

## Configuration

The following global varialbes can be defined in the **Lua** file for the program configuration.
- _FILES_ - defines the group of files for processing. When the varialbe is defined then commands can be called without file name (i.e. _file_ option can be skipped). Some commands do not work with the group of files. Operations with individual files are still available.
- _DIR_ - defines the name of the directory for storing backup files.  If it is defined, each file in subdirectories must be matched with short names using key-value notation (otherwise, a file _a/b/c_ will be saved as _DIR/a/b/c_, i.e. the subdirectories _DIR/a/b_ must exist).
- _BRANCH_ - use it to define the default branch name, in this case the _branch_ option can be skipped from the command.
- _MERGEREM_ - set it equal _true_ to add removed lines into the file to resolve the conflict. It is _false_ by default. 
- _EXT_ - defines the backup file extention, _bkp_ by default.
- _COLOR_ - use ANSI escape codes to highlight messages.

## Example 

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

## Dependencies 

The library works in **Lua** 5.1-5.4 without additional packages. 
