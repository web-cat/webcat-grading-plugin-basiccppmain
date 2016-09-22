#ifndef __cxxtest__SuiteInitFailureTable_h__
#define __cxxtest__SuiteInitFailureTable_h__

//
// A simple table that keeps track of test suite initialization failures.
//

#include <cstdlib>

namespace CxxTest
{

class SuiteInitFailureTable
{    
private:
    //~ Nested Structures ....................................................

    struct Entry
    {
        Entry* next;
        char* name;
        char* reason;
    };

public:
    //~ Constructors/Destructor ..............................................

    // ----------------------------------------------------------
    SuiteInitFailureTable()
    {
        first_entry = NULL;
    }


    // ----------------------------------------------------------
    ~SuiteInitFailureTable()
    {
        Entry* curr = first_entry;
        
        while (curr)
        {
            free(curr->name);
            free(curr->reason);
            
            Entry* to_delete = curr;
            curr = curr->next;
            free(to_delete);
        }
    }


    //~ Public methods .......................................................
    
    // ----------------------------------------------------------
    void addSuite(const char* name, const char* reason)
    {
        Entry* entry = (Entry*) calloc(1, sizeof(Entry));
        entry->next = NULL;
        entry->name = copyString(name);
        entry->reason = copyString(reason);
        
        entry->next = first_entry;
        first_entry = entry;
    }
    

    // ----------------------------------------------------------
    const char* didSuiteFail(const char* name)
    {
        Entry* curr = first_entry;
        
        while (curr)
        {
            if (strcmp(name, curr->name) == 0)
            {
                return curr->reason;
            }
            
            curr = NULL;
        }
        
        return NULL;
    }

private:
    //~ Private methods ......................................................
    
    // ----------------------------------------------------------
    char* copyString(const char* str)
    {
        size_t len = strlen(str);
        char* copy = (char*) calloc(len + 1, sizeof(char));
        strcpy(copy, str);
        return copy;
    }


    //~ Instance variables ...................................................
    
    Entry* first_entry;
};

extern SuiteInitFailureTable __cxxtest_failed_init_suites;

} // end namespace CxxTest

#endif // __cxxtest__SuiteInitFailureTable_h__
