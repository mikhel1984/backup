#!/usr/local/bin/lua
require "backup"

--   file extention
-- EXT = "bkp"
--   branch name
-- BRANCH = "master"
--   show removed lines in source
-- MERGEREM = true
--   highlight messages
-- COLOR = true
--   save to directory
-- DIR = "foo"
--   file list
FILES = {
-- current directory, simple list
-- "1.txt",
-- other directories, require aliases
-- ["bar/2.txt"] = "bar2.txt", 
}

backup()
