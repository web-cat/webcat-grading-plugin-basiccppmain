#ifndef __cxxtest__ErrorPrinter_h__
#define __cxxtest__ErrorPrinter_h__

//
// The ErrorPrinter is a simple TestListener that
// just prints "OK" if everything goes well, otherwise
// reports the error in the format of compiler messages.
// The ErrorPrinter uses std::cout
//

#include <cxxtest/Flags.h>

#ifndef _CXXTEST_HAVE_STD
#   define _CXXTEST_HAVE_STD
#endif // _CXXTEST_HAVE_STD

#include <cxxtest/ErrorFormatter.h>
#include <cxxtest/StdValueTraits.h>

#ifdef _CXXTEST_OLD_STD
#   include <stdio.h>
#else // !_CXXTEST_OLD_STD
#   include <cstdio>
#endif // _CXXTEST_OLD_STD

namespace CxxTest 
{
    class ErrorPrinter : public ErrorFormatter
    {
    public:
        ErrorPrinter(FILE* o = stdout, const char *preLine = ":", const char *postLine = "") :
            ErrorFormatter( new FileOutputStream(o), preLine, postLine ) {}

        virtual ~ErrorPrinter()
        {
            delete outputStream();
        }
    };
}

#endif // __cxxtest__ErrorPrinter_h__
