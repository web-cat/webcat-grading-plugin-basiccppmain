#!c:\perl\bin\perl.exe
#=============================================================================
#   @(#)$Id: execute.pl,v 1.3 2008/03/24 01:25:53 stedwar2 Exp $
#-----------------------------------------------------------------------------
#   Web-CAT Curator: execute script for Java submissions
#
#   usage:
#       newGbExecute.pl <properties-file>
#=============================================================================

use strict;
use warnings;
use Carp qw( carp croak );
use Cwd qw( abs_path );
use File::Basename;
use File::Copy;
use File::Spec;
use File::stat;
use Proc::Background;
use Config::Properties::Simple;
use Web_CAT::Beautifier;
use Web_CAT::CLOC;
use Web_CAT::FeedbackGenerator;
use Web_CAT::JUnitResultsReader;
use Web_CAT::DerefereeStatsReader;
use Web_CAT::Utilities
    qw( confirmExists filePattern copyHere htmlEscape addReportFile scanTo
        scanThrough linesFromFile addReportFileWithStyle );
use Text::Tabs;
use XML::Smart;
use Data::Dump qw( dump );

die "ANT_HOME environment variable is not set"
    if !defined( $ENV{ANT_HOME} );
my $ANT = "ant";     # "G:\\ant\\bin\\ant.bat";


#=============================================================================
# Bring command line args into local variables for easy reference
#=============================================================================
my $propfile    = $ARGV[0];     # property file name
my $cfg         = Config::Properties::Simple->new( file => $propfile );

my $pid         = $cfg->getProperty( 'pid' );
my $working_dir = $cfg->getProperty( 'workingDir' );
my $script_home = $cfg->getProperty( 'scriptHome' );
my $log_dir     = $cfg->getProperty( 'resultDir' );
my $timeout     = $cfg->getProperty( 'timeout', 45 );

my $maxCorrectnessScore   = $cfg->getProperty( 'max.score.correctness' );
my $maxToolScore          = $cfg->getProperty( 'max.score.tools', 0 );
my $NTprojdir             = $working_dir . "/";

my %status = (
    'instrTestResults'      => undef,
    'instrDerefereeStats'   => undef,
    'feedback'              =>
        new Web_CAT::FeedbackGenerator( $log_dir, 'feedback.html' ),
    'instrFeedback'         =>
        new Web_CAT::FeedbackGenerator( $log_dir, 'staffFeedback.html' )
);

Web_CAT::Utilities::initFromConfig($cfg);

#-------------------------------------------------------
# In addition, some local definitions within this script
#-------------------------------------------------------
my $useSpawn           = 1;
my $postProcessingTime = 20;
my $callAnt            = 1;

my $antLogRelative     = "ant.log";
my $antLog             = "$log_dir/$antLogRelative";
my $scriptLogRelative  = "script.log";
my $scriptLog          = "$log_dir/$scriptLogRelative";
my $compileLogRelative = "compile.log";
my $compileLog         = "$log_dir/$compileLogRelative";
my $testLogRelative    = "test.log";
my $testLog            = "$log_dir/$testLogRelative";
my $instrLogRelative   = "instr.log";
my $instrLog           = "$log_dir/$instrLogRelative";
my $timeoutLogRelative = "timeout.log";
my $timeoutLog         = "$log_dir/$timeoutLogRelative";
my $markupPropFile     = "$script_home/markup.properties";
my $explanationRelative = "explanation.log";
my $explanation        = "$log_dir/$explanationRelative";
my $can_proceed        = 1;
my $runtimeScore       = 0;
my $staticScore        = 0;

my $instructorTestsRun     = 0;
my $instructorTestsFailed  = 0;
my $instructorCasesPercent = 0;
my $totalToolDeductions    = 0;
my $antLogOpened           = 0;


#-------------------------------------------------------
# In the future, these could be set via parameters set in Web-CAT's
# interface
#-------------------------------------------------------
my $debug                = $cfg->getProperty( 'debug',      0 );
my $hintsLimit           = $cfg->getProperty( 'hintsLimit', 3 );
my $expSectionId      = $cfg->getProperty( 'expSectionId', 0 );


my @beautifierIgnoreFiles = ();

my $pathSep = $cfg->getProperty( 'PerlForPlugins.path.separator', ':' );


#=============================================================================
# Generate derived properties for ANT
#=============================================================================
# testCases
my $scriptData = $cfg->getProperty( 'scriptData', '.' );
#my @scriptDataDirs = < $scriptData/* >;
$scriptData =~ s,/$,,;

sub findScriptPath
{
    my $subpath = shift;
    my $target = "$scriptData/$subpath";
#    foreach my $sddir ( @scriptDataDirs )
#    {
#       my $target = $sddir ."/$subpath";
#       #print "checking $target\n";
        if ( -e $target )
        {
            return $target;
        }
#    }
    die "cannot file user script data file $subpath in $scriptData";
}

# testCases
my $testCasePath = "${script_home}/tests";
{
    my $testCaseFileOrDir = $cfg->getProperty( 'testCases' );
    if ( defined $testCaseFileOrDir && $testCaseFileOrDir ne "" )
    {
        my $target = findScriptPath( $testCaseFileOrDir );
        if ( -d $target )
        {
            $cfg->setProperty( 'testCasePath', $target );
        }
        else
        {
            $cfg->setProperty( 'testCasePath', dirname( $target ) );
            $cfg->setProperty( 'testCasePattern', basename( $target ) );
            $target = dirname( $target );
        }
        $testCasePath = $target;
    }
}
$testCasePath =~ s,/,\\,g;

# assignmentIncludes
my $assignmentIncludes;
{
    my $p = $cfg->getProperty( 'assignmentIncludes' );
    if ( defined $p && $p ne "" )
    {
        $assignmentIncludes = findScriptPath( $p );
        $cfg->setProperty( 'assignmentIncludes.abs', $assignmentIncludes );
    }
}

# assignmentLib
my $assignmentLib;
{
    my $p = $cfg->getProperty( 'assignmentLib' );
    if ( defined $p && $p ne "" )
    {
        $assignmentLib = findScriptPath( $p );
        $cfg->setProperty( 'assignmentLib.abs', $assignmentLib );
    }
}

# generalIncludes
my $generalIncludes;
{
    my $p = $cfg->getProperty( 'generalIncludes' );
    if ( defined $p && $p ne "" )
    {
        $generalIncludes = findScriptPath( $p );
        $cfg->setProperty( 'generalIncludes.abs', $generalIncludes );
    }
}

# generalLib
my $generalLib;
{
    my $p = $cfg->getProperty( 'generalLib' );
    if ( defined $p && $p ne "" )
    {
        $generalLib = findScriptPath( $p );
        $cfg->setProperty( 'generalLib.abs', $generalLib );
    }
}

# timeout
my $timeoutForOneRun = $cfg->getProperty( 'timeoutForOneRun', 30 );
$cfg->setProperty( 'exec.timeout', $timeoutForOneRun * 1000 );

$cfg->save();


#=============================================================================
# Prep for output
#=============================================================================
my $DOSStyle_log_dir = $log_dir;
$DOSStyle_log_dir =~ s,/,\\,g;
my $DOSStyle_script_home = $script_home;
$DOSStyle_script_home =~ s,/,\\,g;
my $DOSStyle_NTprojdir = $NTprojdir;
$DOSStyle_NTprojdir =~ s,/,\\,g;
my $DOSStyle_scriptData = $scriptData;
$DOSStyle_scriptData =~ s,/,\\,g;
my $testCasePattern = $cfg->getProperty( 'testCasePattern' );
my $unixTestCasePath = $testCasePath;
$unixTestCasePath =~ s,\\,/,g;

sub regexize_path
{
    # transform a path to a suffix-finding RE like this:
    # from: /a/b/c/d
    # to: ((../)+|/)((((a/)?b/)?c/)?d/)

    my $path = shift;

    $path =~ m,^/?(.*)/?$,;
    $path = $1;
    my $result = "";

    my @components = split( /\//, $path );
    foreach my $i ( 0 .. $#components )
    {
        my $comp = $components[$i];
        $result = "(" . $result . quotemeta($comp) . "/)";
        $result .= "?" if ( $i < $#components );
    }
    
    return $result;
}

sub sanitize_path
{
    my $path = shift;
    $path =~ s,\\,/,g;
    $path =~ s,[A-Z]:,,g;

    my $workdir1 = regexize_path( $working_dir );
    my $workdir2 = regexize_path( abs_path( $working_dir ) );

    my $re = "((\\.\\./)+|/)(" . $workdir1 . "|" . $workdir2 . ")";
    $path =~ s,$re,,gi;
    return $path;
}


sub prep_for_output
{
    my $result = shift;
    # print "before: $result";
    $result =~ s,__student_main,main,gi;

    $result =~ s,([a-z]:)?\Q$log_dir\E(/bin/[^\s]*(:[0-9]+)?:)?,,gi;
    $result =~ s,([a-z]:)?\Q$DOSStyle_log_dir\E(\\bin\\[^\s]*(:[0-9]+)?:)?,,gi;

    # print "\t1: $result";
    $result =~ s,([a-z]:)?\Q$script_home\E(/[^\s]*(:[0-9]+)?:)?,,gi;
    $result =~ s,([a-z]:)?\Q$DOSStyle_script_home\E(\\[^\s]*(:[0-9]+)?:)?,,gi;

    # print "\t2: $result";
    $result =~ s,([a-z]:)?\Q$script_home\E/tests(/[^\s]*(:[0-9]+)?:)?,,gi;
    $result =~
        s,([a-z]:)?\Q$DOSStyle_script_home\E\\tests(\\[^\s]*(:[0-9]+)?:)?,,gi;

    # print "\t3: $result";
    $result =~ s,([a-z]:)?\Q$NTprojdir\E/__/([^\s]*(:[0-9]+)?:)?,,gi;
    $result =~ s,([a-z]:)?\Q$DOSStyle_NTprojdir\E\\__\\([^\s]*(:[0-9]+)?:)?,,gi;
    # print "\t4: $result";
    $result =~ s,([a-z]:)?\Q$NTprojdir\E(/)?,,gi;
    $result =~ s,([a-z]:)?\Q$DOSStyle_NTprojdir\E(/)?,,gi;
    $result = sanitize_path( $result );

    $result =~ s,([a-z]:)?\Q$testCasePath\E(/)?[^:\s]*\.h,\<\<reference tests\>\>,gi;
    $result =~ s,([a-z]:)?\Q$testCasePath\E(/)?,,gi;
    $result =~ s,([a-z]:)?\Q$unixTestCasePath\E(/)?[^:\s]*\.h,\<\<reference tests\>\>,gi;
    $result =~ s,([a-z]:)?\Q$unixTestCasePath\E(/)?,,gi;
    #print "testCasePath = $testCasePath\n";
    #print "unixTestCasePath = $unixTestCasePath\n";
    #print "scriptData = $scriptData\n";
    #print "DOSStyle_scriptData = $DOSStyle_scriptData\n";

    # print "\t4.5: $result";
    $result =~ s,([a-z]:)?\Q$scriptData\E(/)?,,gi;
    $result =~ s,([a-z]:)?\Q$DOSStyle_scriptData\E(/)?,,gi;

    # print "\t5: $result";
    if ( defined( $testCasePattern ) )
    {
        $result =~ s/([^\s]*(\/|\\))?\Q$testCasePattern\E/\<\<reference tests\>\>/gi;
    }
    $result =~ s/([^\s]*(\/|\\))?(_)*instructor(_)*test(s)?\.(h|cpp)/\<\<reference tests\>\>/gio;
    $result =~ s/([^\s]*(\/|\\))?runinstructortests\.cpp/\<\<reference tests\>\>/gio;

    # print "\t6: $result";
    $result =~ s/^[0-9]+:\s*//o;
    $result =~ s/&/&amp;/go;
    $result =~ s/</&lt;/go;
    $result =~ s/>/&gt;/go;
    # print "\t7: $result";
    return expand( $result );
}

#=============================================================================
# Script Startup
#=============================================================================
# Change to specified working directory and set up log directory
chdir( $working_dir );

# try to deduce whether or not there is an extra level of subdirs
# around this assignment
{
    # Get a listing of all file/dir names, including those starting with
    # dot, then strip out . and ..
    my @dirContents = grep(!/^(\..*|META-INF)$/, <* .*> );

    # if this list contains only one entry that is a dir name != src, then
    # assume that the submission has been "wrapped" with an outter
    # dir that isn't actually part of the project structure.
    if ( $#dirContents == 0 && -d $dirContents[0] && $dirContents[0] ne "src" )
    {
        # Strip non-alphanumeric symbols from dir name
        my $dir = $dirContents[0];
        if ( $dir =~ s/[^a-zA-Z0-9_]//g )
        {
            if ( $dir eq "" )
            {
                $dir = "dir";
            }
            rename( $dirContents[0], $dir );
        }
        $working_dir .= "/$dir";
        chdir( $working_dir );
    }
}

print "working dir set to $working_dir\n" if $debug;

if ( $debug > 2 )
{
    print "path = ", $ENV{PATH}, "\n\n";
    if ( defined $ENV{INCLUDE} )
    {
           print "include = ", $ENV{INCLUDE}, "\n\n";
    }
    if ( defined $ENV{LIB} )
    {
        print "lib = ", $ENV{LIB}, "\n\n";
    }
}

{
    my $localFiles = $cfg->getProperty( 'localFiles' );
    if ( defined $localFiles && $localFiles ne "" )
    {
        my $lf = findScriptPath( $localFiles );
        print "localFiles = $lf\n" if $debug;
        if ( -d $lf )
        {
            print "localFiles is a directory\n" if $debug;
            copyHere( $lf, $lf, \@beautifierIgnoreFiles );
            foreach my $f (glob("$lf/*"))
            {
                my $newfile = $f;
                $newfile =~ s,^\Q$lf/\E,,;
                push @beautifierIgnoreFiles, $newfile;
            }
        }
        else
        {
            print "localFiles is a single file\n" if $debug;
            my $base = $lf;
            $base =~ s,/[^/]*$,,;
            copyHere( $lf, $base, \@beautifierIgnoreFiles );

            my $newfile = $lf;
            $newfile =~ s,^\Q$lf/\E,,;
            push @beautifierIgnoreFiles, $newfile;
        }
    }
}
if ( ! -d "$script_home/obj" )
{
    mkdir( "$script_home/obj" );
}



#=============================================================================
# Run ANT script and collect the log
#=============================================================================
my $time1        = time;
my $testsRun     = 0; #0
my $testsFailed  = 0;

if ( $callAnt )
{
    if ( $debug > 2 ) { $ANT .= " -v"; }

    my $cmdline = $Web_CAT::Utilities::SHELL
        . "$ANT -f \"$script_home/build.xml\" -l \"$antLog\" "
        . "-propertyfile \"$propfile\" \"-Dbasedir=$working_dir\" "
        . "2>&1 > " . File::Spec->devnull;

    $ENV{'CYGWIN'} = 'nodosfilewarning';
    
    print $cmdline, "\n" if ( $debug );
    if ( $useSpawn )
    {
        my ( $exitcode, $timeout_status ) = Proc::Background::timeout_system(
                $timeout - $postProcessingTime, $cmdline );

        if ( $timeout_status )
        {
            $can_proceed = 0;
            $status{'feedback'}->startFeedbackSection(
                "Errors During Testing", ++$expSectionId );
            $status{'feedback'}->print( <<EOF );
<p><b class="warn">Testing your solution exceeded the allowable time
limit for this assignment.</b></p>
<p>Most frequently, this is the result of <b>infinite recursion</b>--when
a recursive method fails to stop calling itself--or <b>infinite
looping</b>--when a while loop or for loop fails to stop repeating.
</p>
<p>
As a result, no time remained for further analysis of your code.</p>
EOF
            $status{'feedback'}->endFeedbackSection;
        }
    }
    else
    {
        system( $cmdline );
    }
}

my $time2 = time;
if ( $debug )
{
    print "\n", ( $time2 - $time1 ), " seconds\n";
}
my $time3 = time;


#-----------------------------------------------
# Generate a script warning
sub adminLog {
    open( SCRIPTLOG, ">>$scriptLog" ) ||
        die "Cannot open file for output '$scriptLog': $!";
    print SCRIPTLOG join( "\n", @_ ), "\n";
    close( SCRIPTLOG );
}


#=============================================================================
# check for compiler errors (or warnings) on student test cases
#=============================================================================
if ( $can_proceed )
{
    open( ANTLOG, "$antLog" ) ||
        die "Cannot open file for input '$antLog': $!";
    $antLogOpened++;

    $_ = <ANTLOG>;
    scanTo( qr/^compile:/ );
    scanTo( qr/^\s*\[cc\]/ );
    my $compileMsgs     = "";
    my $compileErrs     = 0;
    my $compileWarnings = 0;
    if ( !defined( $_ )  ||  $_ !~ m/^\s*\[cc\].*files to be compiled/ )
    {
        if ( defined( $_ ) )
        {
            adminLog( "Failed to find '[cc] ... files to be compiled' "
                      . "in line:\n$_" );
        }
        $can_proceed = 0;
        $compileMsgs = "Cannot locate compiler output for analysis.\n";
        $compileErrs++;
    }
    $_ = <ANTLOG>;
    while ( defined( $_ )  &&  ( s/^\s*\[cc\] //o  ||  m/^\s*$/o ) )
    {
        if ( m/^\s*$/o ) { $_ = <ANTLOG>; next; }
        # print "msg: $_";
        if ( m/^(\s*[A-Za-z]:)?[^:]+:([0-9]*:)?\s*error:/o ||
             m/no such file/io ||
             m/ld returned 1 exit status/o )
        {
            # print "err: $_";
            $compileErrs++;
            $can_proceed = 0;
        }
        elsif ( m/^(\s*[A-Za-z]:)?[^:]+:([0-9]*:)?\s*warning:/o )
        {
            # print "warning: $_";
            $compileWarnings++;
            # $can_proceed = 0;
        }
        elsif ( m/^Starting link\s*$/o || m/^ar:/o || m/^a\s+-/o )
        {
            $_ = "";
        }
        $compileMsgs .= prep_for_output( $_ );
        $_ = <ANTLOG>;
    }
    $compileMsgs =~ s/^\s*starting link\s*$//io;
    if ( $compileMsgs ne "" )
    {
        $status{'feedback'}->startFeedbackSection(
            ( $compileErrs )
            ? "Compilation Produced Errors"
            : "Compilation Produced Warnings",
            ++$expSectionId
        );
        $status{'feedback'}->print( "<pre>\n" );
        $status{'feedback'}->print( $compileMsgs );
        $status{'feedback'}->print( "</pre>\n" );
        $status{'feedback'}->endFeedbackSection;
    }
}
elsif ( $debug ) { print "compiler output analysis skipped\n"; }
$time3 = time;
if ( $debug )
{
    print "\n", ( $time3 - $time2 ), " seconds\n";
}


#=============================================================================
# check for compiler errors (or warnings) on instructor test cases
#=============================================================================
if ( $can_proceed )
{
    scanTo( qr/^compileInstructorTests:/ );
    scanTo( qr/^\s*\[cc\]/ );
    my $compileMsgs     = "";
    my $compileErrs     = 0;
    my $collectingMsgs  = 1;
    if ( !defined( $_ )  ||  $_ !~ m/^\s*\[cc\].*files to be compiled/ )
    {
#        adminLog( "Failed to find instructor '[cc] ... files to be compiled' "
#                  . "in line:\n" . ( defined( $_ ) ? $_ : "<null>" ) );
        $compileMsgs = "Cannot locate behavioral analysis output.\n";
        $compileErrs++;
        $can_proceed = 0;
    }
    $_ = <ANTLOG>;
    while ( defined( $_ )  &&  ( s/^\s*\[cc\] //o  ||  m/^\s*$/o ) )
    {
        if ( m/^\s*$/o ) { $_ = <ANTLOG>; next; }
        # print "msg: $_";
        if ( m/^(\s*[A-Za-z]:)?[^:]+:([0-9]*:)?\s*error:/o ||
             m/no such file/io ||
             m/ld returned 1 exit status/o )
        {
            if ( $compileErrs ) { $collectingMsgs = 0; }
            # print "err: $_";
            $compileErrs++;
            $can_proceed = 0;
        }
        if ( m/in (file|member)/io || m/\(Each/o ) {
            do
            {
                print "skipping: $_" if ( $debug > 4 );
                $_ = <ANTLOG>;
            } while ( defined( $_ ) && m/^\s*\[cc\]\s\s+/o );
            next;
        }
        if ( $collectingMsgs )
        {
            $compileMsgs .= prep_for_output( $_ );
        }
        $_ = <ANTLOG>;
    }
    $compileMsgs =~ s/^\s*starting link\s*$//io;
    if ( $compileErrs )
    {
        $status{'feedback'}->startFeedbackSection(
            "Estimate of Problem Coverage",
            $expSectionId );
        $status{'feedback'}->print( <<EOF );
<p><b>Problem coverage: <font color="#ee00bb">unknown</font></b></p><p>
<p>
<font color="#ee00bb">Web-CAT was unable to assess your test cases.</font></p>
<p>For this assignment, the proportion of the problem that is covered by your
test cases is being assessed by running a suite of reference tests against
your solution, and comparing the results of the reference tests against the
results produced by your tests.</p>
<font color="#ee00bb">Your code failed to compile correctly against the
reference tests.</font></p>
<p>This is most likely because you have not named your class(es)
or header file(es) as required in the assignment, have failed to provide
a required method or #include directive, or have failed to use
the required name(s) or signature(s) for a method.
</p><p>Failure to follow these constraints will prevent
the proper assessment of your tests.
</p><p>The following specific error(s) were discovered while compiling
reference tests against your submission:</p>
<pre>
$compileMsgs
</pre>
EOF
        $status{'feedback'}->endFeedbackSection;
    }
}
elsif ( $debug ) { print "instructor test generation analysis skipped\n"; }


#=============================================================================
# collect testing stats for instructor tests
#=============================================================================
if ( $can_proceed )
{
    scanTo( qr/^instructorTest:/ );
    scanTo( qr/^\s*\[exec\]/ );
    my %instrHints  = ();
    my $resultsSeen = 0;
    my $timeoutOccurred = 0;
    my $memwatchLog = "";
    my $instrOutput = "";

    if ( !defined( $_ ) || $_ !~ m/^\s*\[exec\]\s+/ )
    {
        adminLog( "Failed to find [exec] in line:\n"
                  . ( defined( $_ ) ? $_ : "<null>" ) );
        $can_proceed = 0;
        $instrHints{"error: Cannot locate behavioral analysis output.\n"} = 1;
        $instructorTestsFailed++;
    }
    while ( defined( $_ )  &&  ( s/^\s*\[exec\] //o || m/^\s*$/o ) )
    {
        $instrOutput .= $_;

        #print "msg: $_";
        if ( m/^running\s*([0-9]+)\s*tests/io )
        {
            print "stats: $_" if ( $debug > 1 );
            $instructorTestsRun += $1;
            if ( m/^running\s*([0-9]+)\s*tests(.*)\.ok!$/io )
            {
                $resultsSeen++;
            }
        }
        elsif ( m/^failed\s*([0-9]+)\s*of\s*([0-9]+)\s*tests/io )
        {
            print "stats: $_" if ( $debug > 1 );
            $instructorTestsFailed += $1;
            $resultsSeen++;
        }
        elsif ( s/^In .*:$//o )
        {
            # Just ignore messages that point to file locations
        }
        #elsif ( s/^.*(\"?)(SIG[A-Z]*):\s*/$2: /o )
        #{
        #    if ( $1 eq "\"" ) { s/\"$//o; }
        #    # print "hint: $_";
        #    if ( $hintsLimit != 0 )
        #    {
        #        $instrHints{prep_for_output($_)} = 1;
        #    }
        #}
        elsif ( s/^.*(\"?)\bhint:\s*//io )
        {
            if ( $1 eq "\"" ) { s/\"$//o; }
            # print "hint: $_";
            if ( $hintsLimit != 0 )
            {
                $instrHints{prep_for_output($_)} = 1;
            }
        }
        elsif ( s,^/=MEMWATCH=/:\s*,,o )
        {
            $memwatchLog .= prep_for_output($_);
        }
        elsif ( m/^timeout: killed/io )
        {
            $timeoutOccurred++;
        }
        elsif ( m/^\.+ok!$/io )
        {
            $resultsSeen++;
        }
        
        # $testMsgs .= prep_for_output( $_ );
        $_ = <ANTLOG>;
    }

    # Instructor's test log
    # -----------
    $status{'instrFeedback'}->startFeedbackSection(
        "Detailed Reference Test Results", ++$expSectionId, 1 );

    $status{'instrFeedback'}->print(<<EOF);
<p>The results of running the instructor's reference test cases are shown
below.</p>
<pre>
EOF
    $status{'instrFeedback'}->print( $instrOutput );
    $status{'instrFeedback'}->print( "</pre>" );

    $status{'instrFeedback'}->endFeedbackSection;

    if ( !$resultsSeen && $instructorTestsRun > 0 )
    {
        $instructorTestsFailed = $instructorTestsRun;
        print "no results seen, failed = $instructorTestsFailed\n"
            if ( $debug > 1 );
    }
    my $instrHints = "";
    if ( %instrHints || $memwatchLog ne "" )
    {
        my $wantHints = $hintsLimit;
        if ( $wantHints )
        {
            $instrHints = "<p>The following hint(s) may help you locate "
            . "some ways in which your solution and your testing may be "
            . "improved:</p>\n<pre>\n";
            foreach my $msg ( keys %instrHints )
            {
                if ( $msg =~ m/^(assert|SIG)/o )
                {
                    $instrHints .= "hint: " . $msg;
                }
                elsif ( $hintsLimit > 0 )
                {
                    $instrHints .=
                        "hint: "
                        . $msg;
                    $hintsLimit--;
                }
            }
            my @hintKeys = keys %instrHints;
            my $hintCount = $#hintKeys;
            if ( $hintCount > $wantHints )
            {
                $instrHints .= "\n($wantHints of $hintCount hints shown)\n";
            }
        }
        if ( $memwatchLog ne "" )
        {
            if ( length( $instrHints ) )
            {
                $instrHints .= "\n\n";
            }
            else
            {
                $instrHints = "<pre>\n";
            }
            $instrHints .= $memwatchLog;
        }
        $instrHints .= "</pre>";
    }

    $status{'feedback'}->startFeedbackSection(
        "Estimate of Problem Coverage",
        ++$expSectionId );

    if ( $timeoutOccurred )
    {
        $status{'feedback'}->print( <<EOF );
<p><b>Problem coverage: <font color="#ee00bb">unknown</font></b></p><p>
<p><font color="#ee00bb">Testing your solution exceeded the allowable time
limit for this assignment.</font></p>
<p>For this assignment, the correctness of your solution is being assessed
by running a suite of reference tests against your solution and checking that
the results generated by your code are correct.</p>
<p>
In this case, your solution exceeded the time limit while executing
the reference tests.
As a result, no time remained for further analysis of your code.
This issue prevented Web-CAT from properly assessing the correctness of
your solution.
</p>
<p>Most frequently, this is the result of <b>infinite recursion</b>--when
a recursive method fails to stop calling itself--or <b>infinite
looping</b>--when a while loop or for loop fails to stop repeating.
$instrHints
EOF
    }
    elsif ( $instructorTestsRun > 0 &&
         $instructorTestsFailed == $instructorTestsRun )
    {
        $status{'feedback'}->print( <<EOF );
<p><b>Problem coverage: <font color="#ee00bb">unknown</font></b></p><p>
<p><font color="#ee00bb">Your problem setup does not appear to be consistent
with the assignment.</font></p>
<p>For this assignment, the correctness of your solution is being assessed
by running a suite of reference tests against your solution and checking that
the results generated by your code are correct.</p>
<p>
In this case, <b>none of the reference tests pass</b> on your solution,
which may mean that your solution make incorrect assumptions about some
aspect of the required behavior.
This discrepancy prevented Web-CAT from properly assessing the correctness
of your solution.</p>
<p>Double check that you have carefully followed all initial conditions
requested in the assignment in setting up your solution.
</p>$instrHints
EOF
    }
    elsif ( $instructorTestsRun == 0 ||
            $instructorTestsFailed == 0 )
    {
        $instructorCasesPercent = 100;

        $runtimeScore = $maxCorrectnessScore;

        $status{'feedback'}->print( <<EOF );
<p><b>Problem coverage: 100%</b></p><p>
<p>Your solution appears to cover all required behavior for this assignment
and produce correct results against all reference tests.</p>
<p>For this assignment, the correctness of your solution is being assessed
by running a suite of reference tests against your solution and checking that
the results generated by your code are correct.
</p>$instrHints
EOF
    }
    else
    {
        $instructorCasesPercent = $instructorTestsRun > 0 ?
            int(
                ( ( $instructorTestsRun - $instructorTestsFailed ) /
                  $instructorTestsRun ) * 100.0 + 0.5 )
            : 0;

        $runtimeScore =
            $maxCorrectnessScore
            * ( ( $instructorTestsRun - $instructorTestsFailed )
                / $instructorTestsRun );
            
        my $scoreToTenths = int( $runtimeScore * 10 + 0.5 ) / 10;
        my $possible = int( $maxCorrectnessScore * 10 + 0.5 ) / 10;
        $status{'feedback'}->print( <<EOF );
<p><b>Problem coverage: <font color="#ee00bb">$instructorCasesPercent% ($scoreToTenths/$possible points)</font></b></p>
<p>For this assignment, the correctness of your solution is being assessed
by running a suite of reference tests against your solution and checking that
the results generated by your code are correct.</p>
<p>
Differences in test results indicate that your code still contains bugs.
Your code appears to cover
<font color="#ee00bb">only $instructorCasesPercent%</font>
of the behavior required for this assignment. You should test your solution
more thoroughly in order to identify cases where it does not produce correct
results.</p>
<p>Double check that you have carefully followed all initial conditions
requested in the assignment in setting up your solution, and that you
have also met all requirements for a complete solution in the final
state of your program.
</p>$instrHints
EOF
    }

    $status{'feedback'}->endFeedbackSection();

    if ( $can_proceed )
    {
        scanTo( qr/^BUILD FAILED/ );
        if ( defined( $_ )  &&  m/^BUILD FAILED/ )
        {
            warn "ant BUILD FAILED unexpectedly.";
            $can_proceed = 0;
        }
    }

    #
    # Collect student and instructor results from the plist printer
    #
    $status{'instrTestResults'} =
        new Web_CAT::JUnitResultsReader( "$log_dir/instr.inc" );
    $status{'instrDerefereeStats'} =
        new Web_CAT::DerefereeStatsReader( "$log_dir/instr-dereferee.inc" );
}
elsif ( $debug ) { print "instructor test results analysis skipped\n"; }

if ( $antLogOpened )
{
    close( ANTLOG );
    my $headerFile = "$log_dir/ant.header";
    unlink( $headerFile ) if ( -f $headerFile );
}

if ( defined $status{'instrTestResults'}
     && $status{'instrTestResults'}->hasResults )
{
    $cfg->setProperty('instructor.test.results',
                      $status{'instrTestResults'}->plist);
    $cfg->setProperty('instructor.test.executed',
                      $status{'instrTestResults'}->testsExecuted);
    $cfg->setProperty('instructor.test.passed',
                      $status{'instrTestResults'}->testsExecuted
                      - $status{'instrTestResults'}->testsFailed);
    $cfg->setProperty('instructor.test.failed',
                      $status{'instrTestResults'}->testsFailed);
    $cfg->setProperty('instructor.test.passRate',
                      $status{'instrTestResults'}->testPassRate);
    $cfg->setProperty('instructor.test.allPass',
                      $status{'instrTestResults'}->allTestsPass);
    $cfg->setProperty('instructor.test.allFail',
                      $status{'instrTestResults'}->allTestsFail);
}

if ( defined $status{'instrDerefereeStats'}
     && $status{'instrDerefereeStats'}->hasResults )
{
    $cfg->setProperty('instructor.memory.numLeaks',
                      $status{'instrDerefereeStats'}->numLeaks);
    $cfg->setProperty('instructor.memory.leakRate',
                      $status{'instrDerefereeStats'}->leakRate);
    $cfg->setProperty('instructor.memory.totalBytesAllocated',
                      $status{'instrDerefereeStats'}->totalMemoryAllocated);
    $cfg->setProperty('instructor.memory.maxBytesInUse',
                      $status{'instrDerefereeStats'}->maxMemoryInUse);
    $cfg->setProperty('instructor.memory.numCallsToNew',
                      $status{'instrDerefereeStats'}->numCallsToNew);
    $cfg->setProperty('instructor.memory.numCallsToDelete',
                      $status{'instrDerefereeStats'}->numCallsToDelete);
    $cfg->setProperty('instructor.memory.numCallsToArrayNew',
                      $status{'instrDerefereeStats'}->numCallsToArrayNew);
    $cfg->setProperty('instructor.memory.numCallsToArrayDelete',
                      $status{'instrDerefereeStats'}->numCallsToArrayDelete);
    $cfg->setProperty('instructor.memory.numCallsToDeleteNull',
                      $status{'instrDerefereeStats'}->numCallsToDeleteNull);
}

$cfg->setProperty('outcomeProperties', '("instructor.test.results")');


#=============================================================================
# Do static analysis/style checks
#=============================================================================

# %codeMarkupIds is a map from file names to codeMarkup numbers
my %codeMarkupIds = ();

# %codeMessages is a hash like this:
# {
#   filename1 => {
#                  <line num> => {
#                                   category => coverage,
#                                   coverage => "...",
#                                   message  => "..."
#                                },
#                  <line num> => { ...
#                                },
#                },
#   filename2 => { ...
#                },
# }
my %codeMessages = ();
my %codeMarkupRemarks = ();
my %codeMarkupDeductions = ();

# Now process the Vera log file.
my $veraLog = "$log_dir/vera.log";
if ( open ( VERALOG, $veraLog ) )
{
    while ( <VERALOG> )
    {
        chomp;
        if ( m/^(\S*):(?![\/\\])(\d+):(.*)$/o )
        {
            my $path = sanitize_path($1);
            my $line = $2;
            my $msg = $3;

            if (!defined($codeMessages{$path}{$line}))
            {
                $codeMessages{$path}{$line} = {
                    category => 'Error',
                    message  => htmlEscape( $3 ),
                    deduction => 1
                };
            }
            else
            {
                $codeMessages{$path}{$line}{message} .= "<br/>" . htmlEscape($3);
                $codeMessages{$path}{$line}{deduction}++;
            }

            $codeMarkupRemarks{$path}++;
            $codeMarkupDeductions{$path}++;
            $totalToolDeductions++;
        }
    }
    close(VERALOG);
}

# Now process the Doxygen log file.
my $doxyLog = "$log_dir/doxygen_warnings.log";
if ( open ( DOXYLOG, $doxyLog ) )
{
    while ( <DOXYLOG> )
    {
        chomp;
        if ( m/^(\S*):(?![\/\\])(\d+):(.*)$/o )
        {
            my $path = sanitize_path($1);
            my $line = $2;
            my $msg = $3;
            $msg =~ s/^\s*[Ww]arning:\s*//;

            if (!defined($codeMessages{$path}{$line}))
            {
                $codeMessages{$path}{$line} = {
                    category => 'Error',
                    message  => htmlEscape( $msg ),
                    deduction => 1
                };
            }
            else
            {
                $codeMessages{$path}{$line}{message} .= "<br/>" . htmlEscape($msg);
                $codeMessages{$path}{$line}{deduction}++;
            }

            $codeMarkupRemarks{$path}++;
            $codeMarkupDeductions{$path}++;
            $totalToolDeductions++;
        }
    }
    close(DOXYLOG);
}


if ( $debug > 3 )
{
    print "\n\ncode messages:\n--------------------\n";
    foreach my $f ( keys %codeMessages )
    {
        print "$f:\n";
        foreach my $line ( keys %{ $codeMessages{$f} } )
        {
            print "    line $line:\n";
            foreach my $k ( keys %{ $codeMessages{$f}{$line} } )
            {
                print "        $k => ", $codeMessages{$f}{$line}{$k}, "\n";
            }
        }
    }
}

# Compute the final static analysis score
$staticScore  = $maxToolScore - $totalToolDeductions;

if ($staticScore < 0)
{
    $staticScore = 0;
}


#=============================================================================
# generate HTML versions of source files
#=============================================================================

push @beautifierIgnoreFiles, 'runAllTests.cpp';
push @beautifierIgnoreFiles, 'history.xml';
#print @beautifierIgnoreFiles;
my $beautifier = new Web_CAT::Beautifier;
$beautifier->beautifyCwd( $cfg,
                          \@beautifierIgnoreFiles,
                          \%codeMarkupIds,
                          \%codeMessages );


#=============================================================================
# Use CLOC to calculate lines of code statistics
#=============================================================================

my @cloc_files = ();
my $numCodeMarkups = $cfg->getProperty( 'numCodeMarkups', 0 );

if ($numCodeMarkups > 0)
{
    for (my $i = 1; $i <= $numCodeMarkups; $i++)
    {
        my $cloc_file = $cfg->getProperty(
          "codeMarkup${i}.sourceFileName", undef);

        if (defined $cloc_file)
        {
            $cfg->setProperty("codeMarkup${i}.remarks",
                $codeMarkupRemarks{$cloc_file}) if defined $codeMarkupRemarks{$cloc_file};
            $cfg->setProperty("codeMarkup${i}.deductions",
                -$codeMarkupDeductions{$cloc_file}) if defined $codeMarkupDeductions{$cloc_file};

            push @cloc_files, $cloc_file;
        }
    }

    print "Passing these files to CLOC: @cloc_files\n" if ( $debug > 2 );

    my $cloc = new Web_CAT::CLOC;
    $cloc->execute(@cloc_files);

    for (my $i = 1; $i <= $numCodeMarkups; $i++)
    {
        my $cloc_file = $cfg->getProperty(
          "codeMarkup${i}.sourceFileName", undef);

        my $cloc_metrics = $cloc->fileMetrics($cloc_file);
        next unless defined $cloc_metrics;

        $cfg->setProperty(
          "codeMarkup${i}.loc",
          $cloc_metrics->{blank} + $cloc_metrics->{comment} + $cloc_metrics->{code} );
        $cfg->setProperty(
          "codeMarkup${i}.ncloc",
          $cloc_metrics->{blank} + $cloc_metrics->{code} );
    }
}

#=============================================================================
# Update and rewrite properties to reflect status
#=============================================================================

# Student feedback
# -----------
{
    my $rptFile = $status{'feedback'};
    if ( defined $rptFile )
    {
        $rptFile->close;
        if ( $rptFile->hasContent )
        {
            addReportFileWithStyle( $cfg, $rptFile->fileName, 'text/html', 1 );
        }
        else
        {
            $rptFile->unlink;
        }
    }
}

# Instructor feedback
# -----------
{
    my $rptFile = $status{'instrFeedback'};
    if ( defined $rptFile )
    {
        $rptFile->close;
        if ( $rptFile->hasContent )
        {
            addReportFileWithStyle( $cfg, $rptFile->fileName, 'text/html', 1, 'staff' );
        }
        else
        {
            $rptFile->unlink;
        }
    }
}

# Script log
# ----------
if ( -f $scriptLog && stat( $scriptLog )->size > 0 )
{
    addReportFileWithStyle( $cfg, $scriptLogRelative, "text/plain", 0, "admin" );
    addReportFileWithStyle( $cfg, $antLogRelative,    "text/plain", 0, "admin" );
}

$cfg->setProperty( "score.correctness", $runtimeScore );
$cfg->setProperty( "score.tools",       $staticScore  );
$cfg->setProperty( 'expSectionId',      $expSectionId );
$cfg->save();

if ( $debug )
{
    my $lasttime = time;
    print "\n", ( $lasttime - $time1 ), " seconds total\n";
    print "\nFinal properties:\n-----------------\n";
    my $props = $cfg->getProperties();
    while ( ( my $key, my $value ) = each %{$props} )
    {
        print $key, " => ", $value, "\n";
    }
}


#-----------------------------------------------------------------------------
exit( 0 );
#-----------------------------------------------------------------------------
