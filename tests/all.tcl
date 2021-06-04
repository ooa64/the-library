package require tcltest

tcltest::configure {*}$argv -singleproc true -testdir [file dirname [info script]]

rename tcltest::test tcltest::__test
proc tcltest::test args {
    puts stderr [format ">>> %s: %s" [lindex $args 0] [string trim [lindex $args 1]]]
    uplevel 1 tcltest::__test $args
}

tcltest::runAllTests
