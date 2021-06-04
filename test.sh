#!/bin/sh
tclsh tests/all.tcl -verbose bpse $* 2> test.err | tee test.out
