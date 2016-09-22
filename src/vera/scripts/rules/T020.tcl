# Left-parens should not be followed by whitespace; right-parents should not be
# preceded by whitespace

foreach f [getSourceFileNames] {
    foreach t [getTokens $f 1 0 -1 -1 {leftparen rightparen}] {
        set line [lindex $t 1]
        set column [lindex $t 2]
        set type [lindex $t 3]
        
        if {$type == "rightparen"} {
            set preceding [getTokens $f $line 0 $line $column {}]
            if {$preceding != {}} {
                set lastPreceding [lindex [lindex $preceding end] 3]
                if {$lastPreceding == "space"} {
                    report $f $line "Closing parentheses should not be preceded by whitespace."
                }
            }
        } elseif {$type == "leftparen"} {
            set following [getTokens $f $line [expr $column + 1] [expr $line + 1] -1 {}]
            if {$following != {}} {
                set firstFollowing [lindex [lindex $following 0] 3]
                if {$firstFollowing == "space"} {
                    report $f $line "Opening parentheses should not be followed by whitespace."
                }
            }
        }
    }
}
