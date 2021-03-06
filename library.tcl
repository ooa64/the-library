#!/usr/bin/env tclsh
#
# library app

namespace eval library {

    variable DBFILE "library.db"
    variable DBSCHEMA "library.sql"
    variable PAGEROOT "pages"
    variable HTTPPORT 9999
    variable DEBUG 0
    variable server

    proc start {} {
        log "server startup, use the admin login at http://localhost:$::library::HTTPPORT/"
        init $::library::DBSCHEMA $::library::DBFILE
        set ::library::server [socket -server ::library::listen $::library::HTTPPORT]
    }

    proc stop {} {
        close $::library::server
        unset ::library::server
        done
        log "server stopped"
    }

    proc init {dbschema dbfile} {
        log "database opens, datafile $dbfile with schema $dbschema"
        if {$::tcl_platform(platform) eq "windows"} {
            load tclsqlite3.dll sqlite3
        } else {
            package require sqlite3
        }
        sqlite3 ::library::db $dbfile -create true
        db eval {PRAGMA foreign_keys=1}
        db eval {PRAGMA encoding="UTF-8"}
        foreach s [sqlscript $dbschema] {db eval $s}
        if {$::library::DEBUG} {
            trace add execution ::library::db enter \
                    {apply {{cmd op} {::library::debug [lindex [info level -1] 0] $cmd}}}
        }
    }

    proc done {} {
        db close
        log "database closed"
    }

    ### ENGINE ###

    proc listen {chan addr port} {
        log "$chan: connect from $addr:$port"
        try {
            fconfigure $chan -translation {auto lf} -encoding "utf-8"
            if {[getrequest $chan request requestparams]} {
                log "$chan: requested $request$requestparams"
                if {$request eq "/favicon.ico"} {
                    # dismiss an annoying request
                    send $chan 200 "" ""
                } else {
                    # do the job
                    if {[getusername $chan username] && [userstate $username] ne "blocked"} {
                        if {[userstate $username] eq ""} {
                            log "$chan: new reader $username registered"
                            newreader $username
                        }
                        log "$chan: login $username ([userrole $username])"
                        send $chan 200 {*}[process $username $request $requestparams]
                    } else {
                        send $chan 200 "text/html" [readpage login.html]
                    }
                }
            } else {
                send $chan 400 "text/plain" "bad request"
            }
        } on error {result} {
            debug {listen} {$::errorInfo}
            send $chan 500 "text/plain" $result
        }
        close $chan
        log "$chan: connection closed"
    }

    proc getrequest {chan requestvar requestparamsvar} {
        upvar $requestvar request
        upvar $requestparamsvar requestparams
        return [expr {
            [parserequest [gets $chan] method uri] &&
            [parseuri $uri request requestparams] &&
            $method eq "GET"
        }]
    }

    proc getusername {chan usernamevar} {
        upvar $usernamevar username
        while {[gets $chan s] >= 0} {
            if {[parseuser $s user]} {
                set username [string trim [urldecode $user]]
                while {[gets $chan] ne ""} {}
                return [expr {$username ne ""}]
            } elseif {$s eq ""} {
                break
            }
        }
        return false
    }

    proc process {username request requestparams} {
        set userrole [userrole $username]
        set params [params $requestparams]
        if {$request eq "/"} {
            return [list "text/html" [readpage $userrole.html]]
        } elseif {[string match "::library::/*" [info proc ::library::$request]]} {
            return [list "application/json" [::library::$request $username $userrole $params]]
        }
        error "invalid api call"
    }

    proc send {chan code contenttype content} {
        array set codetext {
            200 "OK"
            400 "Bad Request"
            500 "Server Error"
        }
        debug {send} {[string range $content 0 512]}
        puts $chan "HTTP/1.1 $code $codetext($code)\nConnection: close"
        if {$contenttype ne ""} {
            puts $chan "Content-Type: $contenttype\nContent-Length: [string bytelength $content]\n"
            puts -nonewline $chan $content
        } else {
            puts $chan ""
        }
        flush $chan
        log "$chan: sent code $code, [string bytelength $content] bytes"
    }

    ### UTILS ###

    proc parserequest {input methodvar urivar} {
        upvar $methodvar method
        upvar $urivar uri
        regexp {^(\w+)\s+(/.*)\s+(HTTP/[\d\.]+)} $input -> method uri
    }

    proc parseuser {input uservar} {
        upvar $uservar user
        regexp {^\s*Cookie\s*:(?:.*;)?\s*libraryuser\s*=\s*([^;]+?)\s*} $input -> user
    }

    proc parseuri {input callvar paramsvar} {
        upvar $callvar call
        upvar $paramsvar params
        regexp {^(/[^\?]*)(\?.*)?$} $input -> call params
    }

    proc params {params} {
        set d [dict create]
        foreach {- name value} [regexp -inline -all {(?:\?|&)([^=&]*)=([^&]*)} $params] {
            set n [string trim $name]
            set v [string trim [urldecode $value]]
            if {$n ne "" && $v ne ""} {
                dict append d $n $v
            }
        }
        return $d
    }

    proc urldecode {str} {
        set str [string map [list + { } "\\" "\\\\"] $str]
        regsub -all -- {%([A-Fa-f0-9][A-Fa-f0-9])} $str {\\u00\1} str
        encoding convertfrom "utf-8" [subst -novar -nocommand $str]
    }

    proc userrole {username} {
        db onecolumn {select role from user where state = 'active' and name = :username order by role}
    }

    proc userstate {username} {
        db onecolumn {select state from user where name = :username order by role}
    }

    proc newreader {username} {
        db eval {insert into reader(name) values(:username)}
    }

    proc sqlscript {filename} {
        split [readfile $filename] "/"
    }

    proc readpage {page} {
        readfile [file join $::library::PAGEROOT $page]
    }

    proc readfile {filename} {
        set h [open $filename "r"]
        set s [read $h]
        close $h
        return $s
    }

    proc debug {args} {
        if {$::library::DEBUG} {
            catch {uplevel [list subst [join $args \n]]} s
            catch {puts stderr "DEBUG: $s"}
        }
    }

    proc log {args} {
        puts stderr [join $args]
    }

    ### API helpers ###

    proc setvars {params args} {
        # NOTE: creates or updates variables in the caller frame
        set l {}
        foreach n $args {
            if {[dict exists $params $n]} {
                uplevel [list set $n [dict get $params $n]]
                lappend l $n
            }
        }
        return $l
    }

    proc selectfields {fields} {join $fields ","}
    proc jsonfields {fields} {join [lmap n $fields {subst {'$n',$n}}] ","}
    proc updatefields {fields} {join [lmap n $fields {subst {$n=:$n}}] ","}
    proc valuesfields {fields} {join [lmap n $fields {subst {:$n}}] ","}
    proc wherefields {fields} {join [concat "true" [lmap n $fields {subst {$n=:$n}}]] " and "}

    proc dbobject {props sql args} {
        # NOTE: execute query in the caller frame to use sqlite variable binding
        uplevel [list db onecolumn [format \
                [format {select json_object(%s) json from (%s)} [jsonfields $props] $sql] {*}$args]]
    }

    proc dbarray {props sql args} {
        # NOTE: executes query in the caller frame to use sqlite variable binding
        uplevel [list db onecolumn [format \
                [format {select json_group_array(json_object(%s)) json from (%s)} [jsonfields $props] $sql] {*}$args]]
    }

    proc dbupdate {sql args} {
        # NOTE: executes query in the caller frame to use sqlite variable binding
        uplevel [list db onecolumn [format $sql {*}$args]]
    }

    proc checkrole {role args} {
        foreach permitted $args {
            if {$role eq $permitted} {
                return $role
            }
        }
        error "forbidden"
    }

    proc checkvars {vars} {
        if {[llength $vars]} {
            return true
        }
        error "no data"
    }

    ### API ###

    variable USER    {name role state}
    variable BOOK    {id title author publisher published}
    variable REQUEST {id bookid readername title author publisher published returnterm returned state}

    proc /getuser {username userrole params} {
        checkrole $userrole "admin" "librarian" "reader"
        dbobject $::library::USER {select * from user where name=:username} \
    }

    proc /getusers {username userrole params} {
        set vars [setvars $params "name" "role" "state"]
        checkrole $userrole "admin" "librarian"
        dbarray $::library::USER {select * from user where %s order by name,role} \
                [wherefields $vars]
    }

    proc /setreader {username userrole params} {
        checkrole $userrole "admin"
        checkvars [setvars $params "state"]
        checkvars [setvars $params "name"]
        dbupdate {update reader set state=:state where name=:name}
    }

    proc /addlibrarian {username userrole params} {
        checkrole $userrole "admin"
        checkvars [setvars $params "name"]
        dbupdate {insert into librarian(name) values(:name)}
    }

    proc /dellibrarian {username userrole params} {
        checkrole $userrole "admin"
        checkvars [setvars $params "name"]
        dbupdate {delete from librarian where name=:name}
    }

    proc /getbooks {username userrole params} {
        set vars [setvars $params "id" "title" "author" "publisher" "published" "inuse"]
        if {[info exists inuse]} {
            # WORKAROUND: tclsqlite 3.36.0 needs native number for 'inuse'
            set inuse [expr {$inuse}]
        }
        checkrole $userrole "admin" "librarian"
        dbarray [concat $::library::BOOK "inuse"] {
            with bookinuse as (
                select book.*,
                    (select count(*) from request where bookid = book.id) inuse
                from book)
            select * from bookinuse where %s order by id
        } [wherefields $vars]
    }

    proc /querybooks {username userrole params} {
        set fields {"title" "author" "publisher" "published"}
        set vars [setvars $params "title" "author"]
        set orderby ""
        if {[llength [setvars $params "order"]]} {
            # check for sql injection
            if {$order in $fields} {
                if {[llength [setvars $params "reverse"]] && $reverse} {
                    set orderby [format {order by %s desc} $order]
                } else {
                    set orderby [format {order by %s} $order]
                }
            }
        }
        dbarray $fields {select distinct %s from book where %s %s} \
               [selectfields $fields] [wherefields $vars] $orderby
    }

    proc /setbook {username userrole params} {
        set vars [setvars $params "id" "title" "author" "publisher" "published"]
        checkrole $userrole "admin"
        checkvars $vars
        dbupdate {insert or replace into book(%s) values(%s)} \
               [selectfields $vars] [valuesfields $vars]
    }

    proc /delbook {username userrole params} {
        checkrole $userrole "admin"
        checkvars [setvars $params "id"]
        dbupdate {delete from book where id=:id}
    }

    proc /addrequest {username userrole params} {
        set vars [setvars $params "title" "author" "publisher" "published"]
        checkrole $userrole "reader"
        checkvars $vars
        checkvars [setvars [dict create "readername" $username] "readername"]
        dbupdate {insert into request(readername,%s) values(:readername,%s)} \
               [selectfields $vars] [valuesfields $vars]
    }

    proc /setrequest {username userrole params} {
        set vars [setvars $params "bookid" "returnterm"]
        checkrole $userrole "librarian"
        checkvars $vars
        checkvars [setvars $params "id"]
        dbupdate {update request set %s where id=:id} \
               [updatefields $vars]
    }

    proc /delrequest {username userrole params} {
        set vars [setvars $params "id"]
        checkrole $userrole "librarian" "reader"
        checkvars $vars
        if {$userrole eq "reader"} {
            lappend vars {*}[setvars [dict create "readername" $username] "readername"]
        }
        dbupdate {delete from request where %s} \
               [wherefields $vars]
    }

    proc /getrequests {username userrole params} {
        set vars [setvars $params "state"]
        checkrole $userrole "librarian" "reader"
        if {$userrole eq "reader"} {
            lappend vars {*}[setvars [dict create "readername" $username] "readername"]
        } else {
            lappend vars {*}[setvars $params "readername"]
        }
        dbarray $::library::REQUEST {select * from request where %s order by id} \
               [wherefields $vars]
    }

    proc /closerequest {username userrole params} {
        checkrole $userrole "librarian"
        checkvars [setvars $params "id"]
        dbupdate {update request set bookid=null,returned='%s' where id=:id} \
               [clock format [clock seconds] -format "%Y-%m-%d"]
    }
}

if {$argv0 eq [info script]} {
    puts "The Library\n"
    try {
        set library::DEBUG [expr {[lsearch "-debug" $argv] >= 0}]
        library::start
        vwait forever
    } on error {result} {
        library::debug {$::errorInfo}
        library::log "$result"
    }
}
