#!/usr/local/bin/lua
require "backup"

-- file extention
-- EXT = "bkp"
-- branch name
-- BRANCH = "master"

-- save to directory
DIR = "foo"
-- file list
FILES = {
-- current directory
"1.txt",
-- other directories
["bar/2.txt"] = "bar2.txt",
}

backup()
