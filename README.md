# backup

**Lua** based local version control program for text files. The information is stored in _bkp_ files in the same directory where the original files are located. CLI is used to switch between different revisions and do other operations with the file versions.

## Usage
```
./backup.lua file command [option] [branch]
```

Commands and options: 
- **add** _(msg)_ _(branch)_ - save last changes in file
- **rev** _(n)_ _(branch)_ - switch to the n-th revision of the file
- **diff** _(n)_ _(branch)_ - compare current state with the n-th revision
- **log** _(branch)_ - show all commits
- **vs** _file2_ - compare with other file 
- **base** _(n)_ _(branch)_ - update initial commit
- **pop** _(branch)_ - remove last commit
- **summ** _(branch)_ - short summary

Default value for _n_ is the last revision, default _branch_ or _msg_ name is empty string.

## File group

If the project conatains more than one file, it is useful to create _bkplist_ file with the list of all required source names. In this case the program is called in form 
```
./backup.lua command [option] [branch]
```
Only part of operations with the group of files is available, but manipulations with individual files still can be done. The _bkplist_ can define the directory to store _bkp_ files ("DIR = ...", directory must exist) and the name mapping ("source > backup"). For conveniencies, line comments in **Lua** style can be used (but only in the begining of a line).

### Example 

Assume that we want to work with group of files and store _bkp_ in the _foo_ directory. The following three versions of _bkplist_ are equal. 
```
--    1st version
file1         > foo/file1
file2         > foo/file2
path/to/file3 > foo/file3

--    2nd version
DIR = foo
file1         > file1
file2         > file2
path/to/file3 > file3

--    3rd version
DIR = foo
file1
file2
path/to/file3 > file3
```
