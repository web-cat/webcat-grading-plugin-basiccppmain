#ifndef __cxxtest__SafeString_h__
#define __cxxtest__SafeString_h__

//
// A string-like class that is safe for use inside CxxTest and Dereferee
// internals since it uses malloc/realloc/free, rather than new/delete, to
// manage its memory. Functionality is very basic; supports only copying,
// appending, and accessing the base pointer.
//

#include <cstdlib>
#include <cstring>

namespace CxxTest
{

class SafeString
{
public:
    //~ Constructors/Destructor ..............................................
    
    // ----------------------------------------------------------
    /**
     * Constructs an empty string.
     */
    SafeString()
    {
        size = 0;
        capacity = 32;
        
        buffer = (char*) malloc(capacity);
        buffer[0] = '\0';
    }


    // ----------------------------------------------------------
    /**
     * Constructs a new string from the contents of the given C-string.
     */
    SafeString(const char* src)
    {
        size = strlen(src);
        capacity = size + 1;

        buffer = (char*) malloc(capacity);
        strcpy(buffer, src);
    }


    // ----------------------------------------------------------
    /**
     * Constructs a new string from the contents of the given string.
     */
    SafeString(const SafeString& src)
    {
        size = src.length();
        capacity = size + 1;

        buffer = (char*) malloc(capacity);
        strcpy(buffer, src.buffer);
    }


    // ----------------------------------------------------------
    /**
     * Releases any resources used by the string.
     */
    ~SafeString()
    {
        free(buffer);
    }


    // ----------------------------------------------------------
    /**
     * Assigns the contents of the specified string to this string.
     */
    SafeString& operator=(const SafeString& rhs)
    {
        if (this != &rhs)
        {
            if (capacity < rhs.length() + 1)
            {
                free(buffer);
                capacity = rhs.length() + 1;
                buffer = (char*) malloc(capacity);
            }

            size = rhs.length();
            strcpy(buffer, rhs.buffer);
        }
        
        return *this;
    }


    // ----------------------------------------------------------
    /**
     * Assigns the contents of the specified C-string to this string.
     */
    SafeString& operator=(const char* rhs)
    {
        int len = strlen(rhs);

        if (capacity < len + 1)
        {
            free(buffer);
            capacity = len + 1;
            buffer = (char*) malloc(capacity);
        }

        size = len;
        strcpy(buffer, rhs);

        return *this;
    }


    // ----------------------------------------------------------
    /**
     * Assigns the specified character to this string.
     */
    SafeString& operator=(char ch)
    {
        if (capacity < 2)
        {
            free(buffer);
            capacity = 2;
            buffer = (char*) malloc(capacity);
        }

        size = 1;
        buffer[0] = ch;
        buffer[1] = '\0';

        return *this;
    }


    //~ Public methods .......................................................

    // ----------------------------------------------------------
    /**
     * Appends the contents of another SafeString to this string.
     */
    SafeString& operator+=(const SafeString& rhs)
    {
        int newLength = length() + rhs.length();
        int lastLocation = length();

        if (newLength >= capacity)
        {
            capacity = newLength + 1;

            if (rhs.length() == 1)
            {
                capacity *= 2;
            }

            char * newBuffer = (char*) malloc(capacity);
            strcpy(newBuffer, buffer);
            free(buffer);
            buffer = newBuffer;
        }

        strcpy(buffer + lastLocation, rhs.c_str());
        size = newLength;

        return *this;
    }


    // ----------------------------------------------------------
    /**
     * Appends a single character to this string.
     */
    SafeString& operator+=(char ch)
    {
        SafeString temp;
        temp = ch;
        *this += temp;
        return *this;
    }


    // ----------------------------------------------------------
    /**
     * Appends the contents of a C-string to this string.
     */
    SafeString& operator+=(const char* rhs)
    {
        SafeString temp(rhs);
        *this += temp;
        return *this;
    }


    // ----------------------------------------------------------
    /**
     * Appends a single character to this string and returns the new string.
     */
    SafeString operator+(char ch) const
    {
        SafeString result(*this);
        result += ch;
        return result;
    }


    // ----------------------------------------------------------
    /**
     * Appends a C-string to this string and returns the new string.
     */
    SafeString operator+(const char* str) const
    {
        SafeString result(*this);
        result += str;
        return result;
    }


    // ----------------------------------------------------------
    /**
     * Appends another SafeString to this string and returns the new string.
     */
    SafeString operator+(const SafeString& str) const
    {
        SafeString result(*this);
        result += str;
        return result;
    }


    // ----------------------------------------------------------
    /**
     * Gets a value indicating whether or not the string is empty.
     */
    bool empty() const
    {
        return size == 0;
    }


    // ----------------------------------------------------------
    /**
     * Gets the length of the string.
     */
    int length() const
    {
        return size;
    }


    // ----------------------------------------------------------
    /**
     * Gets the pointer to the characters in this string.
     */
    const char* c_str() const
    {
        return buffer;
    }


private:
    //~ Instance variables ...................................................

    char* buffer;
    int size;
    int capacity;
};

} // end namespace CxxTest


#endif // __cxxtest__SafeString_h__
