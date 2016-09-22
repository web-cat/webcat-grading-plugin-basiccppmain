# control structures should have complete curly-braced block of code

foreach fileName [getSourceFileNames] {

    set state "start"
    foreach token [getTokens $fileName 1 0 -1 -1 {for if else while leftparen rightparen leftbrace semicolon}] {
        set type [lindex $token 3]

        if {$state == "control"} {
            if {$type == "leftparen"} {
                incr parenCount
            } elseif {$type == "rightparen"} {
                incr parenCount -1
                if {$parenCount == 0} {
                    set state "expectedblock"
                }
            }
        } elseif {$state == "foundelse"} {
            if {$type != "if" && $type != "leftbrace"} {
                set line [lindex $token 1]
                report $fileName $line "Use full blocks {...}, not single statements, after if/else/for/while."
            }
            set state "block"
        } elseif {$state == "expectedblock"} {
            if {$type != "leftbrace"} {
                set line [lindex $token 1]
                report $fileName $line "Use full blocks {...}, not single statements, after if/else/for/while."
            }
            set state "block"
        }

        if {$type == "for" || $type == "if" || $type == "while"} {
            set parenCount 0
            set state "control"
        } elseif {$type == "else"} {
            set state "foundelse"
        }
    }
}
