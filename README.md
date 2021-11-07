# backup

Lua based program for 'version control' of text files. The information is stored in _bkp_ files in the same directory where the original files are located. CLI is used to switch between different revisions and do other operations with the file versions.

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

Default value for _n_ is the last revision, default _branch_ name is the empty string.
