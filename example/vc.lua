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

-- save to directory
DIR = "foo"
-- file list
FILES = {
-- current directory
"1.txt",
-- other directory
"bar/2.txt",
}

backup()
