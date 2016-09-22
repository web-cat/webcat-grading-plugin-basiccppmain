# Line cannot be too long

set maxLength [getParameter "max-line-length" 80]

foreach f [getSourceFileNames] {
    set lineNumber 1
    foreach line [getAllLines $f] {
        if {[string length $line] > $maxLength} {
            report $f $lineNumber "Lines should not be longer than ${maxLength} characters."
        }
        incr lineNumber
    }
}
