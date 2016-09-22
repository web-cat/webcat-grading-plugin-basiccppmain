#!c:\perl\bin\perl.exe
#=============================================================================
# A stupid hack to make a file processable by Doxygen if it doesn't have any
# comments.
#=============================================================================

print "/** \@file */";
open (INPUT, "$ARGV[0]");
foreach (<INPUT>)
{
    print $_;
}
