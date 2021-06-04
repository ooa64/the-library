#!/bin/sh
# tcl \
exec wish $0 ${1+$@}

#
# $Id: sqlitenav.tcl 170 2008-09-01 14:48:23Z oleinickoa $
#
# SQLite Navigator, version 0.23
# Written by Oleg Oleinick, ooa64@ua.fm
#
# HINTS:
#
# - Use Control-{Left,Right,Up,Down} to resize windows;
#
# - Use Control-{N,P} to see next/prev query in query editor;
#
# - Use Insert, Return, Delete in data panel to insert, edit, delete row.
#
# - Use right mouse button in data panel to change rows order.
#
# CHANGES:
#
# 0.25  Attach dialogs to the main window.
#       Fixed options file name on windows 10.
#       Fixed triggers menu.
#       Preserve info panel content when info panel selected (tk8.6)
# 0.24  Key parameter for encrypted database.
# 0.23  Fixed error when editing field with single quote.
# 0.22  Fixed error when importing single quote.
# 0.21  Batch mode.
# 0.20  Functions table changed from 'sqlite_source' to 'sqlite$source'.
#       Resizable text fields in the row editor.
# 0.19  Sqlite 3.1 compatibility (select rowid as rowid ...)
# 0.18  Fixed 'Vacuum/Check' error message for sqlite < 2.4.0
# 0.17  Option -sqlitelib to specify sqlite shared library.
#       Sqlite 3.0 compatibility (ColumnName does not return column name)
# 0.16  Sqlite 2.8.? compatibility (ColumnName returns column type).
# 0.15  Functions.
# 0.14  Option -encoding to specify database encoding. Very slow.
# 0.13  Sqlite 2.7.6 compatibility (ColumnCount had become a no-op).
# 0.12  Database can be specified as a first command line parameter.
#       Options saving fixed.
# 0.11  Column width limit (-widthlimit) - workaround for buggy Windows 95/98.
# 0.10  display triggers (sqlite 2.5.0+).
# 0.9 - display views (sqlite 2.4.0+) and indexes .
# 0.8 - small changes in sqlite package loading.
# 0.7 - multiline fields in data editor, ordered rows (main window)
# 0.6 - workaround for sqlite 2.0 .. 2.1.2 DROP TABLE bug
# 0.5 - improved header for query results, removed 'explain' help.
# 0.4 - sqlite2 compatibility, you can select sqlite version
#       using command line switch -version 1.0 or -version 2.0.
# 0.3 - fixed empty query result for 'explain' and 'select...order by',
# 0.2 - data editor (main window), fixed rc-file corruption.
#

lappend auto_path [file join [file dirname [info script]] .. lib]

package require Tk 8.3

wm withdraw .
wm title . "SQLite Navigator 0.25"

array set OPT {
    -geom       ""
    -path       ""
    -encoding   ""
    -key        ""
    -objtype    table
    -infotype   script
    -sqlheight  10
    -propfont   "Helvetica 10"
    -monofont   "Courier 12 bold"
    -querylimit 100
    -widthlimit 1000
    -querypath  ~/
    -exportpath ~/
    -history    ~/.sqlitenav
    -historylimit 100
    -debug 0
}

# additional options for batch mode
#
# -batch "sqlitenav.sql"
# -outfile "sqlitenav.out"
# -outquote "\""
# -outfs ","
# -outrs "\n"
# -outforce 0
# -outverbose 0

set OPTFILE [file normalize ~/.sqlitenavrc.tcl]
set SQLITE sqlite

if {[file exists $OPTFILE] && [catch {source $OPTFILE} result]} {
    tk_messageBox -type ok -icon error \
        -title "Error loading rcfile" \
        -message $result
    exit 1
}

if {$argc && [string index [lindex $argv 0] 0] != "-"} {
    set OPT(-path) [lindex $argv 0]
    set argv [lrange $argv 1 end]
    set argc [llength $argv]
}

if {$argc && [string index [lindex $argv 0] 0] != "-"} {
    set OPT(-batch) [lindex $argv 0]
    set argv [lrange $argv 1 end]
    set argc [llength $argv]
}

if {[catch {array set OPT $argv}]} {
    tk_messageBox -type ok -icon error \
        -title "Error in command line" \
        -message "Command line switches:\n[join [lsort [array names OPT]] \n]"
    exit 1
}

if {$OPT(-debug)} {
    catch {console show; update idle}
}

if {[info exists OPT(-sqlitelib)] && [file readable $OPT(-sqlitelib)]} {
    if {[catch {load $OPT(-sqlitelib) sqlite} result] \
            && [catch {load $OPT(-sqlitelib) sqlite3} result]} {
        tk_messageBox -type ok -icon error \
            -title "Error loading sqlite" \
            -message "Cant load $OPT(-sqlitelib):\n$result"
        exit 1
    }
} elseif {[info exists OPT(-version)]} {
    set v [expr { $OPT(-version) >= 3.0 ? 3 : "" }]
    if { [catch {package require sqlite$v} result] \
             && [catch {load tclsqlite$v[info sharedlibextension] sqlite$v} result] } {
        tk_messageBox -type ok -icon error \
            -title "Error loading sqlite" \
            -message "Cant find tclsqlite$v library:\n$result"
        exit 1
    }
    unset v
} elseif {[catch {package require sqlite} result] \
            && [catch {package require sqlite3} result] \
            && [catch {load tclsqlite[info sharedlibextension] sqlite} result]
            && [catch {load tclsqlite3[info sharedlibextension] sqlite3} result] } {
    tk_messageBox -type ok -icon error \
        -title "Error loading sqlite" \
        -message "Cant find any tcl sqlite library:\n$result"
    exit 1
}

if {[info commands sqlite3] == "sqlite3"} {
    set SQLITE sqlite3
}

set OPT(-version) [package require $SQLITE]

# workaround for incorrect package version (2.0 instead of 2.1+)
if {$OPT(-version) == "2.0"} {
    catch {regexp {(\d+\.\d+)} [$SQLITE -version] OPT(-version)}
}

catch {wm geometry . $OPT(-geom)}

option add *font                     $OPT(-propfont)
option add *navigator.tables*font    $OPT(-monofont)
option add *text*font                $OPT(-monofont)
option add *text-header*font         $OPT(-monofont)
option add *data*font                $OPT(-monofont)
option add *data-header*font         $OPT(-monofont)
option add *sql*font                 $OPT(-monofont)
option add *navigator.functions*font $OPT(-monofont)

bind all <<ChangeFont>> {
    catch {%W configure -font [option get %W font widgetDefault]}
    foreach w [winfo children %W] {
        event generate $w <<ChangeFont>>
    }
}

# My preferences

#ption add *borderWidth             1           widgetDefault
option add *Scrollbar*width         16          widgetDefault
option add *Scrollbar*takeFocus     0           widgetDefault
option add *Scrollbar*highlightThickness 0      widgetDefault
option add *Checkbutton*padY        0           widgetDefault
option add *Radiobutton*padY        0           widgetDefault
option add *Button*padY             0           widgetDefault

option add *background              LightGrey   widgetDefault
option add *foreground              Black       widgetDefault
option add *selectBackground        \#c3c3c3    widgetDefault
option add *selectForeground        Black       widgetDefault
option add *selectColor             \#d9d9d9    widgetDefault
option add *Listbox*background      \#d9d9d9    widgetDefault
option add *Text*background         White       widgetDefault
option add *Entry*background        White       widgetDefault
option add *Listbox*selectMode      extended    widgetDefault
option add *toolbar*Button*relief   flat        widgetDefault
option add *text-header*relief      raised      widgetDefault
option add *data-header*relief      raised      widgetDefault
option add *function.text*height    10          widgetDefault
option add *function.text*width     40          widgetDefault

bind Button <Left>          {focus [tk_focusPrev %W]}
bind Button <Right>         {focus [tk_focusNext %W]}
bind Button <Up>            {focus [tk_focusPrev %W]}
bind Button <Down>          {focus [tk_focusNext %W]}
bind Button <Return>        {%W invoke; break}
bind Radiobutton <Left>     {focus [tk_focusPrev %W]}
bind Radiobutton <Right>    {focus [tk_focusNext %W]}
bind Radiobutton <Up>       {focus [tk_focusPrev %W]}
bind Radiobutton <Down>     {focus [tk_focusNext %W]}
bind Radiobutton <Return>   {%W invoke; break}
bind Listbox <1>            {+focus %W}
bind Listbox <2>            {+focus %W}
bind Listbox <3>            {+focus %W}

# /My

array set DBS {}

# general tools

proc listaddunique {listname item {limit 0}} {
    upvar $listname list
    if {[set i [lsearch -exact $list $item]] >= 0} {
        set list [lreplace $list $i $i]
    }
    if {$limit && [set i [llength $list]] >= $limit} {
        set list [lreplace $list 0 [expr {$i - $limit}]]
    }
    lappend list $item
}

proc listboxselect {listbox index} {
    if {![catch {$listbox index $index} index]} {
        $listbox activate $index
        $listbox see $index
        $listbox selection clear 0 end
        $listbox selection set $index
        event generate $listbox <<ListboxSelect>>
        update
        return 1
    } else {
        return 0
    }
}

proc resize {widget dim inc} {
#   puts "[winfo req$dim $widget] ?? [winfo req$dim [winfo toplevel $widget]] ;\
#         [winfo    $dim $widget] ?? [winfo    $dim [winfo toplevel $widget]]"
    set size [$widget cget -$dim]
    incr size $inc
    if {$inc < 0} {
        if {$size < 1} {
            set size 1
        }
    } elseif {[winfo req$dim $widget] >= [winfo $dim [winfo toplevel $widget]]} {
        return
    }
    $widget configure -$dim $size
    update idletasks
}

proc evaldebug {command args} {
    tclLog "$command $args"
    return [uplevel [list $command] $args]
}

proc evaleach {commands args} {
    foreach c $commands {
        eval [list $c] $args
    }
}

proc scroolbarcreate {box {axis y}} {
    array set orient {y vertical x horizontal}
    scrollbar $box-${axis}sb -orient $orient($axis) -command "$box ${axis}view"
    $box config -${axis}scrollcommand "$box-${axis}sb set"
    return $box-${axis}sb
}

proc scrollbarset {scrollbar view pos fract} {
    $scrollbar set $pos $fract
    $view xview moveto $pos
}

proc absolutepath {file} {
     set cwd [pwd]
     set real [file join $cwd $file]
     while {1} {
         cd [file dirname $real]
         set dir [pwd]
         set file [file tail $real]
         if {[catch {file readlink $file} real]} break
     }
     cd $cwd
     return [file join $dir $file]
}

proc datafileinfo {path name {ext {tbl}}} {
    set l [list $name]
    if {[catch {file lstat [file join $path $name.$ext] a}]} {
        lappend l N/A N/A N/A N/A
    } else {
        lappend l $a(size) \
            [clock format $a(ctime) -format {%Y-%m-%d %H:%M:%S}] \
            [clock format $a(mtime) -format {%Y-%m-%d %H:%M:%S}] \
            [clock format $a(atime) -format {%Y-%m-%d %H:%M:%S}]
    }
    return $l
}

proc setencoding {encoding} {
    catch {rename encode {}}
    catch {rename decode {}}
    if {[catch {encoding convertto $encoding ""}]} {
        set encoding ""
    }
    if {$encoding == ""} {
        proc encode s {set s}
        proc decode s {set s}
    } else {
        proc encode s "encoding convertfrom \[encoding convertto $encoding \$s\]"
        proc decode s "encoding convertfrom $encoding \[encoding convertto \$s\]"
    }
    return $encoding
}
set OPT(-encoding) [setencoding $OPT(-encoding)]

proc parseparameters {parameters} {
    set parameterslist {}
    if {[string trim $parameters] != ""} {
        foreach parameter [split $parameters ,] {
            if {[regexp {([^=]+)=?(.*)} $parameter => parameter default]} {
                if {[catch {lappend parameterslist [eval list $parameter $default]}]} {
                    lappend parameterslist $parameter
                }
            }
        }
        if {$parameter == ""} {
            lappend parameterslist args
        }
    }
    return $parameterslist
}

proc createparameters {parameterslist} {
    set parameters {}
    foreach parameter $parameterslist {
        if {[llength $parameter] > 1} {
            lappend parameters "[lindex $parameter 0]=\"[lindex $parameter 1]\""
        } else {
            lappend parameters $parameter
        }
    }
    if {[lindex $parameters end] == "args"} {
        return [join [lreplace $parameters end end {}] ,]
    } else {
        return [join $parameters ,]
    }
}

proc createfunction {db persistent name parameters text} {
    global OPT DBS

    if {[info exists DBS($db,path)]} {
        if {[info exists DBS($db,interp)]} {
            if {$persistent} {
                if {[$db eval {pragma table_info('sqlite$source')}] == ""} {
                    $db eval {
                        create table sqlite$source (
                            language,
                            name,
                            parameters,
                            text,
                            primary key (language, name)
                        )
                    }
                }
                set query {
                    replace into sqlite$source (language,name,parameters,text)
                    values ('tcl','%s','%s','%s')
                }
                $db eval [format $query \
                              [encode [string map {' ''} $name]] \
                              [encode [string map {' ''} $parameters]] \
                              [encode [string map {' ''} $text]]]
            }
            if {$OPT(-debug)} {
                tclLog "interp eval $DBS($db,interp) [list proc $name [parseparameters $parameters] $text]"
            }
            interp eval $DBS($db,interp) [list proc $name [parseparameters $parameters] $text]
            $db function $name [list execfunction $db $name]
        }
    }
}

proc dropfunction {db persistent name} {
    global OPT DBS

    if {[info exists DBS($db,path)]} {
        if {[info exists DBS($db,interp)]} {
            if {$OPT(-debug)} {
                tclLog "interp eval $DBS($db,interp) [list rename $name {}]"
            }
            interp eval $DBS($db,interp) [list rename $name {}]
            if {$persistent} {
                if {[$db eval {pragma table_info('sqlite$source')}] != ""} {
                    $db eval [encode "delete from sqlite\$source where language='tcl' and name = '$name'"]
                }
            }
        }
    }
}

proc execfunction {db name args} {
    global OPT DBS

    if {$OPT(-debug)} {
        tclLog "interp eval $DBS($db,interp) [list $name $args]"
    }
    interp eval $DBS($db,interp) [list $name] $args
}

proc loadfunctions {db} {
    global DBS

    if {[info exists DBS($db,path)]} {
        if {![info exists DBS($db,interp)]} {
            set DBS($db,interp) [interp create -safe]
            interp eval $DBS($db,interp) [list set tcl_platform(user) $::tcl_platform(user)]
            if {[$db eval {pragma table_info('sqlite$source')}] != ""} {
                set query {
                    select name,parameters,text
                    from sqlite$source
                    where language = 'tcl'
                }
                foreach {name parameters text} [decode [$db eval [encode $query]]] {
                    createfunction $db false $name $parameters $text
                }
            }
        }
    }
}

proc unloadfunctions {db} {
    global DBS

    if {[info exists DBS($db,interp)]} {
        interp delete $DBS($db,interp)
        unset DBS($db,interp)
    }
}

proc querycolumns {db query} {
    global OPT
    set query [string trimleft $query]
    set columns {}
    if {[string match -nocase "explain*" $query]} {
        set columns {addr opcode p1 p2 p3}
    } elseif {$OPT(-version) >= 3.0} {
	# FIXME: workarount for getting column names, can be expensive ?
        if {![catch {$db eval "[encode $query]" a {break}} result]} {
            set columns $a(*)
        }
    } elseif {![catch {$db eval "explain [encode $query]"} result]} {
        foreach {addr opcode p1 p2 p3} $result {
            if {$opcode == "ColumnName"} {
                lappend columns [decode $p3]
                if {$p2 != "0"} {
                    break
                }
            }
        }
    }
    return $columns
}

#
# database
#

proc db:connect {{path ""}} {
    global DBS OPT SQLITE

    if {$OPT(-version) < 2} {
        set pathselect {tk_chooseDirectory -title "Select database directory"}
    } else {
        set pathselect {tk_getOpenFile -title "Select database file"}
    }
    if {[set path [string trim $path]] != "" || [set path [eval $pathselect]] != ""} {
        catch {set path [absolutepath $path]}
        if {[main:disconnect main-db]} {
            set cmd "$SQLITE main-db $path"
            if {$OPT(-key) != ""} {
                append cmd " -key $OPT(-key)"
            }
            if {[catch $cmd result]} {
                tk_messageBox -type ok -icon error \
                    -title "Error opening $path" -message $result
            } elseif {[catch {main-db eval "select * from sqlite_master" a break} result]} {
                tk_messageBox -type ok -icon error \
                    -title "Invalid database" \
                    -message [decode $result]
            } else {
                if {$OPT(-debug)} {
                    rename main-db main-db-debug
                    interp alias {} main-db {} evaldebug main-db-debug
                }
                set OPT(-path) $path
                set DBS(main-db,path) $path
                set DBS(main-db,queries) {}
                set DBS(main-db,functions) {}
                set DBS(main-db,history) {}
                if {$OPT(-version) > 2} {
                    if {[catch {loadfunctions main-db} result]} {
                        tk_messageBox -type ok -icon error \
                            -title "Error loading functions" \
                            -message [decode $result]
                    }
                }
                return 1
            }
        }
    }
    return 0
}

proc db:disconnect {db} {
    global DBS OPT

    if {[info exists DBS($db,path)]} {
        unloadfunctions $db
        array unset DBS $db,*
        $db close
        if {[info procs $db] == $db} {
            rename $db {}
        }
    }
}

proc db:batch {path batch} {
    global OPT
    global _progress _progress_querycount _progress_querylines _progress_totallines

    set rc 1
    if {[db:connect $OPT(-path)]} {
        if {[info exists OPT(-outfile)]} {
            set outfile $OPT(-outfile)
        } else {
            set outfile ""
        }
        toplevel            .progress
        wm withdraw         .progress
        wm title            .progress "SQLiteNav Progress"
        wm protocol         .progress WM_DELETE_WINDOW {set _progress cancel}
        grid [label .progress.l1 -text "Batch"] [label .progress.l2 -text $batch]
        grid [label .progress.l3 -text "Output"] [label .progress.l4 -text $outfile]
        grid [label .progress.l5 -text "Query No"] [label .progress.l6 -textvar _progress_querycount]
        grid [label .progress.l7 -text "Query Lines"] [label .progress.l8 -textvar _progress_querylines]
        grid [label .progress.l9 -text "Total Lines"] [label .progress.lA -textvar _progress_totallines]
        grid [button .progress.b1 -text Cancel -command {set _progress cancel}] -
        set                 _progress_querycount 0
        set                 _progress_querylines 0
        set                 _progress_totallines 0
        wm deiconify        .progress
        tkwait visibility   .progress
        raise               .progress
        focus               .progress.b1
        set                 _progress ""
        if {[catch { update
            set sock [open $batch "r"]
            fconfigure $sock -encoding [encoding system]
            set queries [split [read $sock] \;]
            close $sock
            if {$outfile != ""} {
                set sock [open $outfile "w+"]
                fconfigure $sock -encoding [encoding system]
            } else {
                set sock ""
            }
            if {[info exists OPT(-outfs)]} {
                set outfs [subst -nocommands -novariables $OPT(-outfs)]
            } else {
                set outfs ","
            }
            if {[info exists OPT(-outrs)]} {
                set outrs [subst -nocommands -novariables $OPT(-outrs)]
            } else {
                set outrs "\n"
            }
            if {[info exists OPT(-outquote)]} {
                set outquote [subst -nocommands -novariables $OPT(-outquote)]
            } else {
                set outquote "\""
            }
            if {[string length $outquote] == 1 && [string is print $outquote]} {
                set outmap [list \\ \\\\ $outquote \\$outquote]
            } else {
                set outmap {}
            }
            foreach query $queries {
                if {![string eq [set query [string trim $query]] ""]} {
                    if {[info exists OPT(-outverbose)] && $OPT(-outverbose)} {
                        if {$sock != "" } {
                            puts $sock "\nSQLITENAV QUERY: $query"
                        }
                    }
                    # update dialog
                    incr _progress_querycount
                    set  _progress_querylines 0
                    update
                    if {[catch {
                        if {$sock != "" && [info exists OPT(-outverbose)] && $OPT(-outverbose)} {
                            set showcolumns 1
                        } else {
                            set showcolumns 0
                        }
                        main-db eval "pragma short_column_names = 0"
                        main-db eval "pragma full_column_names = 1"
                        main-db eval "pragma empty_result_callbacks = 0"
                        main-db eval [encode $query] a {
                            if { $showcolumns } {
                                set showcolumns 0
                                puts $sock "SQLITENAV COLUMNS: [join $a(*) ,]"
                            }
                            set l {}
                            foreach f $a(*) {
                                set v [string map $outmap [decode $a([encode $f])]]
                                lappend l "$outquote$v$outquote"
                            }
                            if {$sock != "" } {
                                puts -nonewline $sock "[join $l $outfs]$outrs"
                            }
                            # update dialog
                            incr _progress_querylines
                            incr _progress_totallines
                            update
                            if {$_progress == "cancel"} {
                                error "Interrupted by user"
                            }
                        }
                    } result]} {
                        if {[info exists OPT(-outforce)] && $OPT(-outforce)} {
                            catch {puts $sock "\nSQLITENAV ERROR: $result"}
                        } else {
                            error $result
                        }
                    }
                }
            }
            if {$sock != "" } {
                close $sock
            }
        } result]} {
            destroy .progress
            db:disconnect main-db
            if {$sock != "" } {
                catch {puts $sock "\nSQLITENAV ERROR: $result"}
                catch {close $sock}
            }
            tk_messageBox -type ok -icon error \
                -title "Error executing batch file $batch" \
                -message [decode $result]
        } else {
            destroy .progress
            db:disconnect main-db
            set rc 0
        }
        unset _progress _progress_querycount _progress_querylines _progress_totallines
    }
    return $rc
}

#
# query and display result
#

proc showquery {db query box {limit 0} {editable 0} {position {}}} {
    global DBS OPT

    set header $box-header

    $box config -listvariable {}
    $box delete 0 end
    $header config -listvariable {}
    $header delete 0 end
    array unset DBS $db,query-$box-*

    update idletasks
    if {[info exists DBS($db,path)]} {
        array unset DBS $db,query-$box-*
        set DBS($db,query-$box-all) 1
        set count 0
        set columns [querycolumns $db $query]
        if {$editable && \
                 ! [regsub {(^\s?select\s)(.*)(\sfrom\s.*$)} $query \
                            "\\1rowid rowid,[join $columns ,]\\3" query]} {
            set editable 0
        }
        set rowids {}
        set data {}
        foreach f $columns {
            set width($f) [string length $f]
        }
        if {[catch {
            $db eval [encode $query] a {
                if {$limit && $count == $limit} {
                    set DBS($db,query-$box-all) 0
                    break
                }
                set l {}
                foreach f $columns {
                    regsub -all {[[:cntrl:]]} [decode $a([encode $f])] . v
                    if {[string length $v] > $width($f)} {
                        set width($f) [string length $v]
                    }
                    lappend l $v
                }
                lappend data $l
                if {$editable} {
                    lappend rowids $a(rowid)
                }
                incr count
                update idletasks
            }
        } result]} {
            if {$result != ""} {
                tk_messageBox -parent [winfo toplevel $box] -type ok -icon error \
                    -title "Query error" -message [decode $result]
                array unset DBS $db,query-$box-*
                return 0
            }
        }
        if {$editable} {
            set DBS($db,query-$box-rowids) $rowids
        }
        set s ""
        foreach f $columns {
            if {$width($f) <= $OPT(-widthlimit)} {
                append s " %-$width($f)s "
            } else {
        set w [expr {$OPT(-widthlimit) - 3}]
                append s " %-${w}.${w}s... "
            }
        }

        $header insert end [eval format [list $s] $columns]

        foreach l $data {
            lappend DBS($db,query-$box-data) [eval format [list $s] $l]
        }
        if {!$DBS($db,query-$box-all)} {
            lappend DBS($db,query-$box-data) \
                [string repeat . [string length [lindex $DBS($db,query-$box-data) 0]]]
        }

        $box config -listvariable DBS($db,query-$box-data)
        if {$position != ""} {
            listboxselect $box $position
        }
        set DBS($db,query-$box-sql) $query
        set DBS($db,query-$box-count) $count
        set DBS($db,query-$box-columns) $columns
        return 1
    }
    return 0
}

#
# query window
#

proc query:init {} {
    global DBS OPT

    if {[info exists DBS(main-db,path)]} {
        for {set i 0} {[winfo exists .query$i]} {incr i} {}
        set w [toplevel .query$i]
        wm withdraw $w
        wm title $w "SQLite Query: $DBS(main-db,path)"
        wm geometry $w [wm geometry .]
        wm group $w .
        pack [frame $w.toolbar] -side top -fill x
        pack [button $w.toolbar.save -text "Save" -command [list query:save $w]] -side left
        pack [button $w.toolbar.load -text "Load" -command [list query:load $w]] -side left
        pack [button $w.toolbar.execute -text "Execute-F8" -command [list query:execute $w]] -side left
        pack [button $w.toolbar.explain -text "Explain-F9" -command [list query:execute $w explain]] -side left
        pack [button $w.toolbar.close -text "Close" -command [list query:close $w]] -side right
        pack [text $w.sql -wrap none -height $OPT(-sqlheight)] -fill x

        pack [frame $w.result] -fill both -expand 1
        grid rowconfig $w.result 1 -weight 1
        grid columnconfig $w.result 0 -weight 1
        grid [listbox $w.result.data-header -takefocus 0 -height 1] -sticky we
        grid [listbox $w.result.data] -sticky news
        grid [scroolbarcreate $w.result.data y] -column 1 -row 1 -sticky ns
        grid [scroolbarcreate $w.result.data x] -column 0 -row 2 -sticky we

        $w.result.data configure -xscrollcommand \
            "scrollbarset $w.result.data-xsb $w.result.data-header"
        $w.result.data-header configure -xscrollcommand \
            "scrollbarset $w.result.data-xsb $w.result.data"
        $w.result.data-xsb configure -command \
            "evaleach {$w.result.data-header $w.result.data} xview"

        bind $w <Control-n>         [list query:history $w +1]
        bind $w <Control-N>         [list query:history $w +1]
        bind $w <Control-p>         [list query:history $w -1]
        bind $w <Control-P>         [list query:history $w -1]
        bind $w <Control-Up>        [list resize $w.sql height -1]
        bind $w <Control-Down>      [list resize $w.sql height +1]
        bind $w <Control-Return>    [list $w.toolbar.execute invoke]
        bind $w <F8>                [list $w.toolbar.execute invoke]
        bind $w <F9>                [list $w.toolbar.explain invoke]
        wm protocol $w WM_DELETE_WINDOW [list $w.toolbar.close invoke]

        update idletasks
        wm deiconify $w
        focus $w.sql
        lappend DBS(main-db,queries) $w
        set DBS(main-db,history-$w-list) $DBS(main-db,history)
        set DBS(main-db,history-$w-index) [llength $DBS(main-db,history)]
        set DBS(main-db,history-$w-current) {}
    }
}

proc query:save {w} {
    global OPT

    set sql [$w.sql get 1.0 end-1char]
    if {$sql != "" && [set file [tk_getSaveFile -parent $w \
            -filetypes {{{SQL files} .sql} {{All files} *.*}} \
            -initialdir $OPT(-querypath) -defaultextension .sql \
            -title "Save query"]] != ""} {
        if {[catch {puts -nonewline [set sock [open $file w]] $sql} result]} {
            tk_messageBox -type ok -icon error -title "Save error" -message $result
        }
        catch {close $sock}
        set OPT(-querypath) [file dirname $file]
    }
}

proc query:load {w} {
    global DBS OPT

    if {[set file [tk_getOpenFile -parent $w \
            -filetypes {{{SQL files} .sql} {{All files} *.*}} \
            -initialdir $OPT(-querypath) -defaultextension .txt \
            -title "Load query"]] != ""} {
        if {[catch {
            set sock [open $file r]
            fconfigure $sock -encoding [encoding system]
            set sql [read $sock]
        } result]} {
            tk_messageBox -type ok -icon error -title "Load error" -message $result
        } else {
            $w.sql delete 1.0 end
            $w.sql insert end $sql
            set DBS(main-db,history-$w-index) [llength $DBS(main-db,history-$w-list)]
            set DBS(main-db,history-$w-current) {}
        }
        catch {close $sock}
        set OPT(-querypath) [file dirname $file]
    }
}

proc query:execute {w {prefix ""}} {
    global DBS OPT

    if {[info exists DBS(main-db,path)]} {
        set prefix [expr {$prefix == "" ? "" : "$prefix "}]
        set query [string trim [$w.sql get 1.0 end]]
        if {$query != "" && [showquery main-db "$prefix$query" $w.result.data $OPT(-querylimit)]} {
            listaddunique DBS(main-db,history-$w-list) $query\n $OPT(-historylimit)
            set DBS(main-db,history-$w-index) [expr {[llength $DBS(main-db,history-$w-list)] - 1}]
            set DBS(main-db,history-$w-current) {}
        }
    }
}

proc query:history {w {rel 0}} {
    global DBS

    set l [llength $DBS(main-db,history-$w-list)]
    set i $DBS(main-db,history-$w-index)
    if {$i >= $l} {
        set DBS(main-db,history-$w-current) [$w.sql get 1.0 end-1char]
    }
    set i [expr {[incr i $rel] < 0 ? 0 : [expr {$i > $l ? $l : $i}]}]
    set DBS(main-db,history-$w-index) $i
    if {$i < $l} {
        $w.sql delete 1.0 end
        $w.sql insert end [lindex $DBS(main-db,history-$w-list) $i]
    } else {
        $w.sql delete 1.0 end
        $w.sql insert end $DBS(main-db,history-$w-current)
    }
}

proc query:close {w} {
    global DBS

    foreach i $DBS(main-db,history-$w-list) {
        listaddunique DBS(main-db,history) $i
    }
    if {[set i [lsearch -exact $DBS(main-db,queries) $w]] >= 0} {
        set DBS(main-db,queries) [lreplace $DBS(main-db,queries) $i $i]
    }
    array unset DBS main-db,history-$w-*
    array unset DBS main-db,query-$w-*
    destroy $w
}

#
# functions window
#

proc functions:init {} {
    global DBS OPT

    if {[info exists DBS(main-db,path)]} {
        for {set i 0} {[winfo exists .functions$i]} {incr i} {}
        set w [toplevel .functions$i]
        wm withdraw $w
        wm title $w "SQLite Functions: $DBS(main-db,path)"
        wm geometry $w [wm geometry .]
        wm group $w .
        pack [frame $w.toolbar] -side top -fill x
        pack [frame $w.navigator] -side left -fill y
        pack [frame $w.information] -side right -fill both -expand 1

        pack [button $w.toolbar.create -text "Create" -command [list functions:rename $w new]] -side left
        pack [button $w.toolbar.rename -text "Rename" -command [list functions:rename $w]] -side left
        pack [button $w.toolbar.drop -text "Drop" -command [list functions:drop $w]] -side left
        pack [button $w.toolbar.refresh -text "Refresh" -command [list functions:show $w]] -side left
        pack [button $w.toolbar.update -text "Update-F8" -command [list functions:update $w no]] -side left
        pack [button $w.toolbar.execute -text "Test-F9" -command [list functions:test $w]] -side left
        pack [button $w.toolbar.close -text "Close" -command [list functions:close $w]] -side right

        pack [listbox $w.navigator.functions] -side left -fill y -expand 1
        pack [scroolbarcreate $w.navigator.functions] -side right -fill y

        grid [label $w.information.name -anchor w] -column 0 -row 0
        grid [label $w.information.parameters -anchor w] -column 1 -row 0
        grid [frame $w.information.panel] -column 0 -row 1 -columnspan 3 -sticky news
        grid rowconfig $w.information 1 -weight 1
        grid columnconfig $w.information 2 -weight 1

        grid [text $w.information.panel.text -wrap none] -sticky news
        grid [scroolbarcreate $w.information.panel.text y] -column 1 -row 0 -sticky ns
        grid [scroolbarcreate $w.information.panel.text x] -column 0 -row 1 -sticky we
        grid rowconfig $w.information.panel 0 -weight 1
        grid columnconfig $w.information.panel 0 -weight 1

        bind $w.navigator.functions <<ListboxSelect>> [list functions:info $w]
        bind $w <Control-Left>  [list resize $w.navigator.functions width -1]
        bind $w <Control-Right> [list resize $w.navigator.functions width +1]
        bind $w <F8>                    [list $w.toolbar.update invoke]
        bind $w <F9>                    [list $w.toolbar.execute invoke]
        wm protocol $w WM_DELETE_WINDOW [list $w.toolbar.close invoke]

        update idletasks
        wm deiconify $w

        lappend DBS(main-db,functions) $w

        functions:show $w 0
    }
}

proc functions:show {w {select ""}} {
    global DBS

    functions:update $w

    $w.navigator.functions delete 0 end
    if {[info exists DBS(main-db,path)]} {
        array unset DBS main-db,functions-$w-*
        if {[main-db eval {pragma table_info('sqlite$source')}] != ""} {
            set query {
                select name,parameters,text
                from sqlite$source
                where language = 'tcl'
            }
            if {[catch {
                set functions {}
                main-db eval [encode $query] data {
                    set name       [decode $data(name)]
                    set parameters [decode $data(parameters)]
                    set text       [decode $data(text)]
                    set DBS(main-db,functions-$w-$name-parameters) $parameters
                    set DBS(main-db,functions-$w-$name-text) $text
                    lappend functions $name
                }
            } result]} {
                array unset DBS main-db,functions-$w-*
                tk_messageBox -parent $w -type ok -icon error \
                    -title "Query error" -message [decode $result]
                return
            }
            foreach function [lsort $functions] {
                $w.navigator.functions insert end $function
            }
        }
        if {![listboxselect $w.navigator.functions $select]} {
            functions:info $w
        }
    }
}

proc functions:info {w} {
    global DBS

    functions:update $w

    $w.information.name config -text ""
    $w.information.parameters config -text ""
    $w.information.panel.text delete 0.0 end

    if {[info exists DBS(main-db,path)] && \
            [llength [$w.navigator.functions curselection]] == 1} {
        set name [$w.navigator.functions get [lindex [$w.navigator.functions curselection] 0]]
        $w.information.name config -text $name
        $w.information.parameters config -text ($DBS(main-db,functions-$w-$name-parameters))
        $w.information.panel.text insert end $DBS(main-db,functions-$w-$name-text)
    }
}

proc functions:rename {w {source ""}} {
    global OPT DBS $w-function

    if {![info exists DBS(main-db,path)] || \
            ![info exists DBS(main-db,interp)]} {
        return
    }

    functions:update $w

    switch -- $source {
        "new" {
            set name ""
            set parameters ""
            set text ""
            set title "Create function"
        }
        default {
            set name [$w.information.name cget -text]
            if {[info exists DBS(main-db,functions-$w-$name-text)]} {
                set parameters $DBS(main-db,functions-$w-$name-parameters)
                set text $DBS(main-db,functions-$w-$name-text)
                set title "Rename function $name"
            } else {
                return
            }
        }
    }

    toplevel    $w.function
    wm withdraw $w.function
    wm title    $w.function $title
    wm geometry $w.function +[winfo rootx $w]+[winfo rooty $w]
    wm protocol $w.function WM_DELETE_WINDOW [list set $w-function cancel]
    wm resizable $w.function 1 0

    grid [label $w.function.lname -text name -anchor e] [entry $w.function.ename] -sticky we
    grid [label $w.function.lparameters -text parameters -anchor e] [entry $w.function.eparameters] -sticky we
    grid [frame $w.function.buttons] -columnspan 2 -pady 8 -sticky news
    foreach i {ok cancel} {
        pack [button $w.function.buttons.$i -text [string totitle $i] -command "set $w-function $i"] \
             -side left -fill x -expand 1
    }
    grid columnconfig $w.function 1 -weight 1

    catch {$w.function.ename configure -font $OPT(-monofont)}
    catch {$w.function.eparameters configure -font $OPT(-monofont)}

    $w.function.ename insert end $name
    $w.function.eparameters insert end $parameters

    update idletasks

    wm deiconify      $w.function
    tkwait visibility $w.function
    raise             $w.function
    grab              $w.function
    focus -force      $w.function
    tkwait variable   $w-function
    set ename        [$w.function.ename get]
    set eparameters  [$w.function.eparameters get]
    destroy           $w.function

    if {[set $w-function] != "cancel"} {
        set ename [string trim $ename]
        set eparameters [createparameters [parseparameters $eparameters]]
        if {$ename != ""} {
            createfunction main-db true $ename $eparameters $text
            if {$name != "" && $ename != $name} {
                dropfunction main-db true $name
            }
            functions:show $w end
        }
    }
    unset $w-function
}

proc functions:update {w {ask yes}} {
    global DBS

    set name [$w.information.name cget -text]
    if {[info exists DBS(main-db,functions-$w-$name-text)]} {
        set parameters $DBS(main-db,functions-$w-$name-parameters)
        set text [$w.information.panel.text get 0.0 end-1chars]
        if {$text != $DBS(main-db,functions-$w-$name-text) && \
                (!$ask || [tk_messageBox -parent $w \
                               -type yesno \
                               -icon question \
                               -title "Save changes" \
                               -message "Text was changed\nSave?"] == "yes")} {
            createfunction main-db true $name $parameters $text
            set DBS(main-db,functions-$w-$name-text) $text
        }
    }
}

proc functions:test:param {w action} {
    global OPT DBS

    set frame $w.function.parameters
    set nexti [lindex [grid size $frame] 1]
    switch -- $action {
        add {
            if {[winfo exists $frame.l$nexti]} {
                grid $frame.l$nexti $frame.e$nexti $frame.d$nexti -sticky news
            } elseif {$nexti && [$frame.l[expr {$nexti - 1}] cget -text] == "args"} {
                grid \
                    [label $frame.l$nexti -text args -anchor e] \
                    [entry $frame.e$nexti] \
                    [label $frame.d$nexti -text {{}} -anchor w] \
                    -sticky we
            }
        }
        del {
            if {$nexti} {
                set i [expr {$nexti - 1}]
                if {[$frame.d$i cget -text] != ""} {
                    grid forget $frame.l$i $frame.e$i $frame.d$i
                }
                if {[focus] == "$frame.e$i"} {
                    if {$i} {
                        focus $frame.e[expr {$i-1}]
                    }
                }
            }
        }
    }
    update idletasks
}

proc functions:test:run {w {usesql 1}} {
    global DBS

    $w.function.text delete 0.0 end
    set name [$w.information.name cget -text]
    set frame $w.function.parameters
    set nexti [lindex [grid size $frame] 1]
    if {$usesql} {
        set values {}
        for {set i 0} {$i < $nexti} {incr i} {
            lappend values '[$frame.e$i get]'
        }
        #puts [list main-db eval "select $name\([join $values ,]) from sqlite_master limit 1"]
        catch {join [main-db eval "select $name\([join $values ,]) from sqlite_master limit 1"]} result
    } else {
        set values {}
        for {set i 0} {$i < $nexti} {incr i} {
            lappend values [$frame.e$i get]
        }
        #puts [list interp eval $DBS(main-db,interp) [concat $name $values]]
        catch {interp eval $DBS(main-db,interp) [concat $name $values]} result
    }
    $w.function.text insert end $result
}

proc functions:test {w} {
    global OPT DBS $w-function

    if {![info exists DBS(main-db,path)] || \
            ![info exists DBS(main-db,interp)]} {
        return
    }

    functions:update $w

    set name [$w.information.name cget -text]

    if {$name == ""} {
        return
    }

    toplevel    $w.function
    wm withdraw $w.function
    wm title    $w.function "Test function $name"
    wm geometry $w.function +[winfo rootx $w]+[winfo rooty $w]
    wm protocol $w.function WM_DELETE_WINDOW [list set $w-function cancel]

    grid [frame $w.function.parameters] -columnspan 2 -sticky we
    set i 0
    foreach p [parseparameters $DBS(main-db,functions-$w-$name-parameters)] {
        if {[llength $p] > 1} {
            set l [lindex $p 0]
            set d [lrange $p 1 end]
        } elseif {$p == "args"} {
            set l [lindex $p 0]
            set d [list {}]
        } else {
            set l $p
            set d ""
        }
        grid \
            [label $w.function.parameters.l$i -text $l -anchor e] \
            [entry $w.function.parameters.e$i] \
            [label $w.function.parameters.d$i -text $d -anchor w] \
            -sticky we
        catch {$w.function.e$i configure -font $OPT(-monofont)}
        incr i
    }
    if {$i} {
        focus $w.function.parameters.e0
    }

    grid columnconfig $w.function.parameters 1 -weight 1

    if {[info exists d] && $d != ""} {
        grid [frame $w.function.parametersbuttons]
        pack [button $w.function.parametersbuttons.add -text "add" -command [list functions:test:param $w add]] -ipady 0 -side left
        pack [button $w.function.parametersbuttons.del -text "del" -command [list functions:test:param $w del]] -ipady 0 -side right
    }

    grid [text $w.function.text -wrap none] -sticky news -row 2
    grid [scroolbarcreate $w.function.text y] -column 1 -row 2 -sticky ns
    grid [scroolbarcreate $w.function.text x] -column 0 -row 3 -sticky we
    grid columnconfig $w.function 0 -weight 1
    grid rowconfig $w.function 2 -weight 1

    grid [frame $w.function.buttons] -columnspan 2 -sticky we
    pack [button $w.function.buttons.testtcl -text "Test" -command [list functions:test:run $w 0]] \
        -side left -fill x -expand 1
    pack [button $w.function.buttons.testsql -text "Execute" -command [list functions:test:run $w 1]] \
        -side left -fill x -expand 1
    pack [button $w.function.buttons.cancel -text Cancel -command "set $w-function cancel"] \
        -side left -fill x -expand 1

    update idletasks

    wm deiconify      $w.function
    tkwait visibility $w.function
    raise             $w.function
    grab              $w.function
    focus -force      $w.function
    tkwait variable   $w-function
    unset             $w-function
    destroy           $w.function
}

proc functions:drop {w} {
    global DBS $w-function

    if {[info exists DBS(main-db,path)]} {
        foreach index [$w.navigator.functions curselection] {
            set name [$w.navigator.functions get $index]
            switch -- \
                [tk_messageBox -parent $w \
                     -type yesnocancel -icon question \
                     -title "Drop function $name" \
                     -message "Drop function $name\nAre you sure?"] {
                         "cancel" break
                         "yes" {
                             dropfunction main-db true $name
                         }
                     }
        }
        functions:show $w
    }
}

proc functions:close {w} {
    global DBS

    functions:update $w

    if {[set i [lsearch -exact $DBS(main-db,functions) $w]] >= 0} {
        set DBS(main-db,functions) [lreplace $DBS(main-db,functions) $i $i]
    }
    array unset DBS main-db,functions-$w-*
    destroy $w
}

#
# main window
#

proc main:init {} {
    pack [frame .toolbar] -side top -fill x
    pack [frame .navigator] -side left -fill y
    pack [frame .information] -side right -fill both -expand 1
    pack [button .toolbar.connect -text "Connect" -command main:connect] -side left
    pack [button .toolbar.refresh -text "Refresh" -command main:showobjs] -side left
    pack [button .toolbar.vacuum -text "Vacuum/Check" -command main:vacuum] -side left
    pack [button .toolbar.query -text "Query" -command query:init] -side left
    pack [button .toolbar.functions -text "Functions" -command functions:init] -side left
    pack [button .toolbar.options -text "Options" -command main:options] -side left
    pack [button .toolbar.exit -text "Exit" -command main:done] -side right
    pack [frame .navigator.toolbar -bd 2 -relief raised] -side top -fill x
    pack [listbox .navigator.tables] -side left -fill y -expand 1
    pack [scroolbarcreate .navigator.tables] -side right -fill y
    foreach i {table view index trigger} {
        pack [radiobutton .navigator.toolbar.$i -text $i -indicatoron 0 \
                  -command main:showobjs -value $i -variable OPT(-objtype)] \
            -side left -fill x -expand 1
    }
    pack [frame .information.toolbar -bd 2 -relief raised] -side top -fill x
    pack [label .information.toolbar.table -width 20 -anchor w] \
        -side left -fill x -expand 1
    foreach i {info script data} {
        pack [radiobutton .information.toolbar.table$i -text $i -indicatoron 0 \
                  -command main:objinfo -value $i -variable OPT(-infotype)] \
            -side left -fill x -expand 1
    }
    pack [frame .information.panel] -fill both -expand 1
    grid rowconfig .information.panel 1 -weight 1
    grid columnconfig .information.panel 0 -weight 1
    grid [listbox .information.panel.text-header -takefocus 0 -height 1] -sticky we
    grid [listbox .information.panel.text] -sticky news
    grid [scroolbarcreate .information.panel.text y] -column 1 -row 1 -sticky ns
    grid [scroolbarcreate .information.panel.text x] -column 0 -row 2 -sticky we

    .information.panel.text configure -xscrollcommand \
        "scrollbarset .information.panel.text-xsb .information.panel.text-header"
    .information.panel.text-header configure -xscrollcommand \
        "scrollbarset .information.panel.text-xsb .information.panel.text"
    .information.panel.text-xsb configure -command \
        "evaleach {.information.panel.text-header .information.panel.text} xview"

    menu .tables
    .tables add command -label Export -command {main:tableutil export}
    .tables add command -label Import -command {main:tableutil import}
    .tables add command -label Vacuum -command {main:tableutil vacuum}
    .tables add command -label Truncate -command {main:tableutil truncate}
    .tables add command -label Drop -command {main:tableutil drop}

    menu .views
    .views add command -label Drop -command {main:viewutil drop}

    menu .indexes
    .indexes add command -label Drop -command {main:indexutil drop}

    menu .triggers
    .triggers add command -label Drop -command {main:triggerutil drop}

    bind .navigator.tables <<ListboxSelect>> main:objinfo
    bind .navigator.tables <3> {
        if {[llength [%W curselection]]} {
            switch $OPT(-objtype) {
                "table"   {set menu .tables}
                "view"    {set menu .views}
                "index"   {set menu .indexes}
                "trigger" {set menu .triggers}
                default {return}
            }
            tk_popup $menu \
                [expr {[winfo rootx %W] + %x}] \
                [expr {[winfo rooty %W] + %y}]
        }
    }
    bind . <Control-Left>  {resize .navigator.tables width -1}
    bind . <Control-Right> {resize .navigator.tables width +1}
    bind .information.panel.text-header <FocusIn> \
        {focus .information.panel.text; listboxselect .information.panel.text active}
    wm protocol . WM_DELETE_WINDOW {.toolbar.exit invoke}
}

proc main:done {} {
    if {[main:disconnect main-db]} {
        exit
    }
}

proc main:connect {{path ""}} {
    global DBS OPT

    if { [db:connect $path] } {
        catch {
            set f [open $OPT(-history)_[string map {: _ \\ _ / _} $path] r]
            set DBS(main-db,history) [split [read $f] \;]
        }
        catch {close $f}
        focus .navigator.tables
        main:showobjs 0
    }
}

proc main:disconnect {db} {
    global DBS OPT

    if {[info exists DBS($db,path)]} {
        if {([llength $DBS($db,queries)] || [llength $DBS($db,functions)]) && \
                [tk_messageBox -type yesno -icon question -title "Close database" \
                     -message "Closing all child windows\nAre you sure?"] != "yes"} {
            return 0
        }
        foreach i $DBS($db,queries) {query:close $i}
        foreach i $DBS($db,functions) {functions:close $i}
        catch {
            set f [open $OPT(-history)_[string map {: _ \\ _ / _} $DBS($db,path)] w]
            puts -nonewline $f [join $DBS($db,history) \;]
        }
        catch {close $f}
        wm title . "SQLite Navigator"
        db:disconnect $db
        main:showobjs
    }
    return 1
}

proc main:showobjs {{select ""}} {
    global OPT DBS

    .navigator.tables delete 0 end
    if {[info exists DBS(main-db,path)]} {
        array unset DBS main-db,table-*
        array unset DBS main-db,index-*
        array unset DBS main-db,view-*
        array unset DBS main-db,trigger-*
        set query {
            select name,sql
            from sqlite_master
            where type = 'table'
        }
        if {[catch {main-db eval [encode $query]} result]} {
            tk_messageBox -parent . -type ok -icon error \
                -title "Query error" -message [decode $result]
            return
        }
        foreach {name sql} [decode [main-db eval [encode $query]]] {
            set DBS(main-db,table-$name-sql) $sql
            set DBS(main-db,table-$name-indices) [list]
            set DBS(main-db,table-$name-triggers) [list]
            set DBS(main-db,table-$name-order) {}
        }
        set query {
            select name,tbl_name,sql
            from sqlite_master
            where type = 'index'
        }
        if {[catch {main-db eval [encode $query]} result]} {
            tk_messageBox -parent . -type ok -icon error \
                -title "Query error" -message [decode $result]
            return
        }
        foreach {name tbl_name sql} [decode $result] {
            set DBS(main-db,index-$name-sql) $sql
            lappend DBS(main-db,table-$tbl_name-indices) $name
        }
        set query {
            select name,sql
            from sqlite_master
            where type = 'view'
        }
        if {[catch {main-db eval [encode $query]} result]} {
            tk_messageBox -parent . -type ok -icon error \
                -title "Query error" -message [decode $result]
            return
        }
        foreach {name sql} [decode [main-db eval [encode $query]]] {
            set DBS(main-db,view-$name-sql) $sql
            set DBS(main-db,view-$name-triggers) [list]
            set DBS(main-db,view-$name-order) {}
        }
        set query {
            select name,tbl_name,sql
            from sqlite_master
            where type = 'trigger'
        }
        if {[catch {main-db eval [encode $query]} result]} {
            tk_messageBox -parent . -type ok -icon error \
                -title "Query error" -message [decode $result]
            return
        }
        foreach {name tbl_name sql} [decode $result] {
            set DBS(main-db,trigger-$name-sql) $sql
            if {[info exists DBS(main-db,table-$tbl_name-triggers)]} {
                lappend DBS(main-db,table-$tbl_name-triggers) $name
            } elseif {[info exists DBS(main-db,view-$tbl_name-triggers)]} {
                lappend DBS(main-db,view-$tbl_name-triggers) $name
            }
        }
        switch -- $OPT(-objtype) {
            "table" {
                foreach index [lsort [array names DBS main-db,table-*-sql]] {
                    .navigator.tables insert end \
                        [lindex [regexp -inline {^main-db,table-(.*)-sql$} $index] 1]
                }
            }
            "view" {
                foreach index [lsort [array names DBS main-db,view-*-sql]] {
                    .navigator.tables insert end \
                        [lindex [regexp -inline {^main-db,view-(.*)-sql$} $index] 1]
                }
            }
            "index" {
                foreach index [lsort [array names DBS main-db,index-*-sql]] {
                    .navigator.tables insert end \
                        [lindex [regexp -inline {^main-db,index-(.*)-sql$} $index] 1]
                }
            }
            "trigger" {
                foreach index [lsort [array names DBS main-db,trigger-*-sql]] {
                    .navigator.tables insert end \
                        [lindex [regexp -inline {^main-db,trigger-(.*)-sql$} $index] 1]
                }
            }
        }
    }
    if {![listboxselect .navigator.tables $select]} {
        main:objinfo
    }
}

proc main:objinfo {} {
    global DBS OPT

    if {![llength [.navigator.tables curselection]] && [focus] eq ".information.panel.text"} {
        # dirty hack to prevent blank panel on tk8.6
        return
    }

    bind .information.panel.text <2> {}
    bind .information.panel.text <3> {}
    bind .information.panel.text <Double-1> {}
    bind .information.panel.text <Return> {}
    bind .information.panel.text <Insert> {}
    bind .information.panel.text <Delete> {}
    .information.panel.text delete 0 end
    .information.panel.text-header delete 0 end
    .information.toolbar.table config -text ""

    if {[info exists DBS(main-db,path)] && \
            [llength [.navigator.tables curselection]] == 1} {
        set obj [.navigator.tables get [lindex [.navigator.tables curselection] 0]]
        .information.toolbar.table config -text $obj
        switch -- $OPT(-infotype) {
            info {
                if {$OPT(-version) < 2} {
                    set s { %-7s  %-21.21s  %10s  %-19s  %-19s  %-19s}
                    .information.panel.text-header insert end \
                        [format $s object \
                             file size created modified accessed size\# created\#]
                    .information.panel.text insert end \
                        [eval format {$s} \
                             Table [datafileinfo $DBS(main-db,path) $obj]]
                    .information.panel.text insert end \
                        [eval format {$s} \
                             Primary [datafileinfo $DBS(main-db,path) ${obj}__primary_key]]
                    foreach i $DBS(main-db,table-$obj-indices) {
                        .information.panel.text insert end \
                            [eval format {$s} Index [datafileinfo $DBS(main-db,path) $i]]
                    }
                } else {
                    switch $OPT(-objtype) {
                        "table" - "view" {set sql "pragma table_info('$obj')"}
                        "index"  {set sql "pragma index_info('$obj')"}
                         default {return}
                    }
                    showquery main-db $sql .information.panel.text
                }
            }
            script {
                switch $OPT(-objtype) {
                    "table" {
                        eval .information.panel.text insert end \
                            [string map {\t {    }} \
                                 [split $DBS(main-db,table-$obj-sql) \n]]
                        foreach index $DBS(main-db,table-$obj-indices) {
                            set sql $DBS(main-db,index-$index-sql)
                            if {$sql != ""} {
                                .information.panel.text insert end ""
                                eval .information.panel.text insert end \
                                    [string map {\t {    }} \
                                         [split $DBS(main-db,index-$index-sql) \n]]
                            }
                        }
                        foreach trigger $DBS(main-db,table-$obj-triggers) {
                            set sql $DBS(main-db,trigger-$trigger-sql)
                            if {$sql != ""} {
                                .information.panel.text insert end ""
                                eval .information.panel.text insert end \
                                    [string map {\t {    }} \
                                         [split $DBS(main-db,trigger-$trigger-sql) \n]]
                            }
                        }
                    }
                    "view" {
                        eval .information.panel.text insert end \
                            [string map {\t {    }} \
                                 [split $DBS(main-db,view-$obj-sql) \n]]
                        foreach trigger $DBS(main-db,view-$obj-triggers) {
                            set sql $DBS(main-db,trigger-$trigger-sql)
                            if {$sql != ""} {
                                .information.panel.text insert end ""
                                eval .information.panel.text insert end \
                                    [string map {\t {    }} \
                                         [split $DBS(main-db,trigger-$trigger-sql) \n]]
                            }
                        }
                    }
                    "index" {
                        eval .information.panel.text insert end \
                            [string map {\t {    }} \
                                 [split $DBS(main-db,index-$obj-sql) \n]]
                    }
                    "trigger" {
                        eval .information.panel.text insert end \
                            [string map {\t {    }} \
                                 [split $DBS(main-db,trigger-$obj-sql) \n]]
                    }
                }
            }
            data {
                switch $OPT(-objtype) {
                    "table" {
                        set sql "select * from $obj"
                        if {[llength $DBS(main-db,table-$obj-order)]} {
                            append sql " order by " \
                                [join $DBS(main-db,table-$obj-order) ,]
                        }
                        showquery main-db $sql \
                            .information.panel.text $OPT(-querylimit) 1
                        bind .information.panel.text <2> {main:setorder}
                        bind .information.panel.text <3> {main:setorder}
                        bind .information.panel.text <Double-1> {main:editrow}
                        bind .information.panel.text <Return> {main:editrow 0}
                        bind .information.panel.text <Insert> {main:editrow 1}
                        bind .information.panel.text <Delete> {main:deleterow}
                    }
                    "view" {
                        set sql "select * from $obj"
                        if {[llength $DBS(main-db,view-$obj-order)]} {
                            append sql " order by " \
                                [join $DBS(main-db,view-$obj-order) ,]
                        }
                        showquery main-db $sql \
                            .information.panel.text $OPT(-querylimit)
                        bind .information.panel.text <2> {main:setorder}
                        bind .information.panel.text <3> {main:setorder}
                    }
                }
            }
        }
    }
}

proc main:setorder {} {
    global DBS OPT TMP _dialog
    set box .information.panel.text

    if {! [info exists DBS(main-db,path)] || \
            ! [info exists DBS(main-db,query-$box-count)]} {
        return
    }

    set objtype $OPT(-objtype)
    if {$objtype != "table" && $objtype != "view"} {
        return
    }

    set obj [.information.toolbar.table cget -text]
    if {$obj == ""} {
        return
    }

    set columns $DBS(main-db,query-$box-columns)

    toplevel    .dialog
    wm withdraw .dialog
    wm title    .dialog "Sort order"
    wm geometry .dialog +[winfo rootx .]+[winfo rooty .]
    wm protocol .dialog WM_DELETE_WINDOW {set _dialog cancel}
    wm resizable .dialog 0 0

    foreach c $columns {
        set TMP($c) 0
        grid [checkbutton .dialog.c$c -variable TMP($c) -text $c -anchor w] -sticky we
    }

    grid [frame .dialog.buttons] -pady 8 -sticky news

    foreach b {ok cancel} {
        pack [button .dialog.buttons.$b -text [string totitle $b] -command "set _dialog $b"] \
             -side left -fill x -expand 1
    }

    foreach c $DBS(main-db,$objtype-$obj-order) {
        set TMP($c) 1
    }

    update idletasks
    wm deiconify      .dialog
    tkwait visibility .dialog
    raise             .dialog
    grab              .dialog
    focus -force      .dialog
    tkwait variable   _dialog
    destroy           .dialog

    if {$_dialog == "ok"} {
        set DBS(main-db,$objtype-$obj-order) {}
        foreach c $columns {
            if {$TMP($c)} {
                lappend DBS(main-db,$objtype-$obj-order) $c
            }
        }
        set sql "select * from $obj"
        if {[llength $DBS(main-db,$objtype-$obj-order)]} {
            append sql " order by " \
                [join $DBS(main-db,$objtype-$obj-order) ,]
        }
        showquery main-db $sql $box $OPT(-querylimit) [expr {$objtype == "table"}]
    }

    unset _dialog
    unset TMP
}

proc main:editrow {{new 0}} {
    global DBS OPT _editor
    set box .information.panel.text

    if {! [info exists DBS(main-db,path)] || \
            ! [info exists DBS(main-db,query-$box-count)]} {
        return
    }

    set table [.information.toolbar.table cget -text]
    if {$table == ""} {
        return
    }

    set columns $DBS(main-db,query-$box-columns)

    if {$new} {
        set rowindex 0
        foreach f $columns {lappend data {}}
    } else {

        set rowindex [lindex [$box curselection] 0]
        if {$rowindex == ""} {
            return
        }

        set rowid [lindex $DBS(main-db,query-$box-rowids) $rowindex]
        if {$rowid == ""} {
            return
        }

        set sql "select [join $columns ,] from $table where rowid = $rowid"
        if {[catch {main-db eval [encode $sql]} data]} {
            tk_messageBox -parent [winfo toplevel .information] -type ok -icon error \
                -title "Refresh error" -message [decode $data]
            return
        }
        set data [decode $data]
    }

    toplevel    .editor
    wm withdraw .editor
    wm title    .editor  [expr {$new ? "New row" : "Edit row"}]
    wm geometry .editor +[winfo rootx .]+[winfo rooty .]
    wm protocol .editor WM_DELETE_WINDOW {set _editor cancel}
    wm resizable .editor 1 0

    set i 0
    foreach f $columns {
        set v [lindex $data $i]
        if {[string first \n $v] >= 0} {
            if {[catch {text .editor.e$f -font $OPT(-monofont)}]} {
                text .editor.e$f
            }
            wm resizable .editor 1 1
            grid rowconfigure .editor [lindex [grid size .editor] 1] -weight 1
            grid [label .editor.l$f -text $f -anchor ne] .editor.e$f -sticky news
            .editor.e$f configure -wrap none -width 40 -height 5
            .editor.e$f insert 0.0 $v
        } else {
            if {[catch {entry .editor.e$f -font $OPT(-monofont)}]} {
                entry .editor.e$f
            }
            grid [label .editor.l$f -text $f -anchor e] .editor.e$f -sticky we
            .editor.e$f insert 0 $v
        }
        incr i
    }

    grid [frame .editor.buttons] -columnspan 2 -pady 8 -sticky news
    grid columnconfig .editor 1 -weight 1
    foreach b {ok cancel} {
        pack [button .editor.buttons.$b -text [string totitle $b] -command "set _editor $b"] \
             -side left -fill x -expand 1
    }

    update idletasks
    wm deiconify      .editor
    tkwait visibility .editor
    raise             .editor
    grab              .editor
    focus -force      .editor
    tkwait variable   _editor

    if {$_editor == "ok"} {
        set values {}
        set fields {}
        set assigns {}
        set i 0
        foreach f $columns {
            if {[winfo class .editor.e$f] == "Text"} {
                set v [.editor.e$f get 0.0 end-1char]
            } else {
                set v [.editor.e$f get]
            }
            if {$v != [lindex $data $i]} {
                set v [string map {' ''} $v]
                lappend fields $f
                lappend values '$v'
                lappend assigns "$f = '$v'"
            }
            incr i
        }
        destroy .editor
        unset _editor

        if {[llength $fields]} {
            if {$new} {
                set sql "insert into $table ([join $fields ,]) values ([join $values ,])"
            } else {
                set sql "update $table set [join $assigns ,] where rowid = $rowid"
            }
            if {[catch {main-db eval [encode $sql]} result]} {
                tk_messageBox -parent [winfo toplevel .information] -type ok -icon error \
                    -title "Database error" -message [decode $result]
            } else {
                set sql "select * from $table"
                if {[llength $DBS(main-db,table-$table-order)]} {
                    append sql " order by " \
                        [join $DBS(main-db,table-$table-order) ,]
                }
                showquery main-db $sql $box $OPT(-querylimit) 1 $rowindex
            }
        }
    } else {
        destroy .editor
        unset _editor
    }
}

proc main:deleterow {} {
    global DBS OPT
    set box .information.panel.text

    if {! [info exists DBS(main-db,path)] || \
            ! [info exists DBS(main-db,query-$box-count)]} {
        return
    }

    set table [.information.toolbar.table cget -text]
    if {$table == ""} {
        return
    }

    set rowindex [lindex [$box curselection] 0]
    set rowids {}
    foreach i [$box curselection] {
        set j [lindex $DBS(main-db,query-$box-rowids) $i]
        if {$j == ""} {
            return
        }
        lappend rowids $j
    }

    if {[llength $rowids]} {
        if {"yes" == [tk_messageBox -type yesno -icon question \
                -title "Delete row(s)" \
                -message "Delete [llength $rowids] row(s) from table $table\nAre you sure?"]} {
            set sql "delete from $table where rowid in ([join $rowids ,])"
            if {[catch {main-db eval [encode $sql]} result]} {
                tk_messageBox -parent [winfo toplevel .information] -type ok -icon error \
                    -title "Database error" -message [decode $result]
            } else {
                showquery main-db "select * from $table" \
                    .information.panel.text $OPT(-querylimit) 1 $rowindex
            }
        }
    }
}

proc main:tableutil {command} {
    global DBS OPT

    foreach i [.navigator.tables curselection] {
        set table [.navigator.tables get $i]
        switch -- $command {
            export {
                if {[set file [tk_getSaveFile \
                        -filetypes {{{Text files} .txt} {{All files} *.*}} \
                        -initialdir $OPT(-exportpath) -defaultextension .txt \
                        -initialfile $table.txt -title "Export table $table"]] != ""} {
                    update idletasks
                    if {[catch {
                        set sock [open $file w]
                        set sql "select * from $table"
                        main-db eval [encode $sql] a {
                            # cant restore \t and \n translation on import 8(
                            set s [string map {\t \\t \n \\n} [decode $a([lindex $a(*) 0])]]
                            foreach f [lrange $a(*) 1 end] {
                                append s \t [string map {\t \\t \n \\n} [decode $a($f)]]
                            }
                            puts $sock $s
                            update idletasks
                        }
                    } result]} {
                        if {$result != ""} {
                            tk_messageBox -type ok -icon error \
                                -title "Export error" -message [decode $result]
                        }
                    }
                    catch {close $sock}
                    set OPT(-exportpath) [file dirname $file]
                } else {
                    break
                }
            }
            import {
                if {[set file [tk_getOpenFile \
                        -filetypes {{{Text files} .txt} {{All files} *.*}} \
                        -initialdir $OPT(-exportpath) -defaultextension .txt \
                        -title "Import table $table"]] != ""} {
                    update idletasks
                    # main-db eval "copy $table from '$file'"
                    # nonstandard way to avoid encoding problems
                    if {[catch {
                        set sock [open $file r]
                        fconfigure $sock -encoding [encoding system]
                        main-db eval "begin transaction"
                        while {![eof $sock]} {
                            switch -glob  -- [set s [gets $sock]] {
                                \\. break
                                ""  continue
                            }
                            set s [string map {' ''} $s]
                            set sql "insert into $table values('[join [split $s \t] ',']')"
                            main-db eval [encode $sql]
                            update idletasks
                        }
                        main-db eval "commit"
                        close $sock
                    } result]} {
                        catch {main-db eval "rollback"}
                        catch {close $sock}
                        tk_messageBox -type ok -icon error \
                            -title "Import error" -message [decode $result]
                    }
                    set OPT(-exportpath) [file dirname $file]
                } else {
                    break
                }
            }
            vacuum {
                foreach index $DBS(main-db,table-$table-indices) {
                    if {![string match "(*)" $index]} {
                        main-db eval [encode "vacuum $index"]
                    }
                }
                catch {main-db eval "vacuum [encode ${table}__primary_key]"}
                main-db eval "vacuum [encode ${table}]"
            }
            truncate {
                switch -- [tk_messageBox -type yesnocancel -icon question \
                               -title "Truncate table $table" \
                               -message "Truncate table $table\nAre you sure?"] {
                                   "cancel" break
                                   "yes" {
                                       main-db eval [encode "delete from $table"]
                                   }
                               }
            }
            drop {
                switch -- [tk_messageBox -type yesnocancel -icon question \
                               -title "Drop table $table" \
                               -message "Drop table $table\nAre you sure?"] {
                                   "cancel" break
                                   "yes" {
                                       foreach index $DBS(main-db,table-$table-indices) {
                                           if {![string match "(*)" $index]} {
                                               main-db eval [encode "drop index $index"]
                                           }
                                       }
                                       main-db eval [encode "drop table $table"]
                                   }
                               }
            }
        }
        .navigator.tables selection clear $i $i
        update idletasks
    }
    main:showobjs
}

proc main:viewutil {command} {
    global DBS OPT

    foreach i [.navigator.tables curselection] {
        set view [.navigator.tables get $i]
        switch -- $command {
            drop {
                switch -- [tk_messageBox -type yesnocancel -icon question \
                           -title "Drop view $view" \
                           -message "Drop view $view\nAre you sure?"] {
                               "cancel" break
                               "yes" {
                                   main-db eval [encode "drop view $view"]
                               }
                           }
            }
        }
        .navigator.tables selection clear $i $i
        update idletasks
    }
    main:showobjs
}

proc main:indexutil {command} {
    global DBS OPT

    foreach i [.navigator.tables curselection] {
        set index [.navigator.tables get $i]
        switch -- $command {
            drop {
                switch -- [tk_messageBox -type yesnocancel -icon question \
                           -title "Drop index $index" \
                           -message "Drop index $index\nAre you sure?"] {
                               "cancel" break
                               "yes" {
                                   if {![string match {(*)} $index]} {
                                       main-db eval [encode "drop index $index"]
                                   }
                               }
                           }
            }
        }
        .navigator.tables selection clear $i $i
        update idletasks
    }
    main:showobjs
}

proc main:triggerutil {command} {
    global DBS OPT

    foreach i [.navigator.tables curselection] {
        set trigger [.navigator.tables get $i]
        switch -- $command {
            drop {
                switch -- [tk_messageBox -type yesnocancel -icon question \
                           -title "Drop trigger $trigger" \
                           -message "Drop trigger $trigger\nAre you sure?"] {
                               "cancel" break
                               "yes" {
                                   main-db eval [encode "drop trigger $trigger"]
                               }
                           }
            }
        }
        .navigator.tables selection clear $i $i
        update idletasks
    }
    main:showobjs
}

proc main:vacuum {} {
    global DBS OPT

    if {[info exists DBS(main-db,path)]} {
        if {$OPT(-version) > 2.4 &&
                [set data [main-db eval "pragma integrity_check"]] != ""} {
            tk_messageBox -type ok -icon info \
                -title "Integrity Check" -message [decode $data]
        }
        main-db eval "vacuum"
        main:showobjs
    }
}

proc main:options {} {
    global OPT OPTFILE _options

    toplevel    .options
    wm withdraw .options
    wm title    .options "SQLiteNav Options"
    wm geometry .options +[winfo rootx .]+[winfo rooty .]
    wm protocol .options WM_DELETE_WINDOW {set _options cancel}
    wm resizable .options 1 0

    set OPT(-geom) [wm geometry .]
    foreach i [lsort [array names OPT]] {
        if {[catch {entry .options.e$i -font $OPT(-monofont) -textvariable OPT($i)}]} {
            entry .options.e$i -textvariable OPT($i)
        }
        grid [label .options.l$i -text [string range $i 1 end] -anchor e] .options.e$i -sticky we
    }
    grid [frame .options.buttons] -columnspan 2 -pady 8 -sticky news
    grid columnconfig .options 1 -weight 1
    foreach i {ok save cancel} {
        pack [button .options.buttons.$i -text [string totitle $i] -command "set _options $i"] \
             -side left -fill x -expand 1
    }
    update idletasks
    wm deiconify      .options
    tkwait visibility .options
    raise             .options
    grab              .options
    focus -force      .options
    tkwait variable   _options
    destroy           .options
    if {$_options != "cancel"} {
        set OPT(-encoding) [setencoding $OPT(-encoding)]
    }
    if {$_options == "save"} {
        catch {
            append s "#<OPT>\n"
            foreach i [lsort [array names OPT]] {
                if {$OPT($i) != ""} {
                    append s "set OPT($i) {$OPT($i)}\n"
                }
            }
            append s "#</OPT>"
            if {[file exists $OPTFILE]} {
                set f [open $OPTFILE "r"]
                set b [read $f]
                close $f
            } else {
                set b ""
            }
            set f [open $OPTFILE "w+"]
            if {![regsub "#<OPT>.*#</OPT>" $b $s b]} {
                append b \n$s\n
            }
            puts -nonewline $f $b
        }
        catch {close $f}
    }
    if {$_options != "cancel"} {
        catch {wm geometry . $OPT(-geom)}
        option add *font                $OPT(-propfont)
        option add *tables*font         $OPT(-monofont)
        option add *text*font           $OPT(-monofont)
        option add *text-header*font    $OPT(-monofont)
        option add *data*font           $OPT(-monofont)
        option add *data-header*font    $OPT(-monofont)
        option add *sql*font            $OPT(-monofont)
        event generate . <<ChangeFont>>
        main:objinfo
    }
    unset _options
}

# go-go-go

if {[info exists OPT(-batch)]} {

    if {$OPT(-debug)} {
        db:batch $OPT(-path) $OPT(-batch)
    } else {
        exit [db:batch $OPT(-path) $OPT(-batch)]
    }

} else {

    main:init

    update idletasks
    wm deiconify .

    main:connect $OPT(-path)

}
