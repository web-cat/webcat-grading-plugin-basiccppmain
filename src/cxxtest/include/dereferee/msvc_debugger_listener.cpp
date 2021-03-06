/*
 *	This file is part of Dereferee, the diagnostic checked pointer library.
 *
 *	Dereferee is free software; you can redistribute it and/or modify
 *	it under the terms of the GNU General Public License as published by
 *	the Free Software Foundation; either version 2 of the License, or
 *	(at your option) any later version.
 *
 *	Dereferee is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *
 *	You should have received a copy of the GNU General Public License
 *	along with Dereferee; if not, write to the Free Software
 *	Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef _CRT_SECURE_NO_DEPRECATE
#define _CRT_SECURE_NO_DEPRECATE
#endif

#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0400

#include <cstdlib>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <string>
#include <windows.h>
#include <dbghelp.h>
#include <crtdbg.h>
#include <dereferee/listener.h>

// ===========================================================================
/**
 * The msvc_debugger_listener class is an implementation of the
 * Dereferee::listener class that either sends its output to the current
 * debugger (if one is present) or to stdout/stderr (if the process is not
 * being debugged). This listener is intended for use on Windows systems
 * with Visual C++ 2005 or higher as the compiler in use.
 *
 * To affect runtime behavior, the following options can be used:
 *
 * - "use.stderr": if set to "true", output will be sent to stderr; otherwise,
 *   it will be sent to stdout (ignored if the process is being debugged)
 * - "output.prefix": if set, the value of this variable will be prepended to
 *   each line of output generated by the listener. This can be useful for
 *   pulling the output of the listener out of a log and processing it later.
 * - "max.leaks.to.report": if set, the integer value of this variable
 *   will be used to specify the maximum number of memory leaks that should be
 *   reported at the end of execution.
 */

// ===========================================================================
/*
 * Messages corresponding to the error codes used by Dereferee.
 */
static const char* error_messages[] =
{
	"Checked pointers cannot point to memory that wasn't allocated with new or new[]",
	"Assigned dead (never initialized) pointer to another pointer",
	"Assigned dead (already deleted) pointer to another pointer",
	"Assigned dead (out of bounds) pointer to another pointer",
	"Called delete instead of delete[] on array pointer",
	"Called delete[] instead of delete on non-array pointer",
	"Called delete on (never initialized) dead pointer",
	"Called delete[] on (never initialized) dead pointer",
	"Called delete on (already deleted or not dynamically allocated) dead pointer",
	"Called delete[] on (already deleted or not dynamically allocated) dead pointer",
	"Dereferenced (never initialized) dead pointer using operator->",
	"Dereferenced (never initialized) dead pointer using operator*",
	"Dereferenced (never initialized) dead pointer using operator[]",
	"Dereferenced (already deleted) dead pointer using operator->",
	"Dereferenced (already deleted) dead pointer using operator*",
	"Dereferenced (already deleted) dead pointer using operator[]",
	"Dereferenced (out of bounds) dead pointer using operator->",
	"Dereferenced (out of bounds) dead pointer using operator*",
	"Dereferenced (out of bounds) dead pointer using operator[]",
	"Dereferenced null pointer using operator->",
	"Dereferenced null pointer using operator*",
	"Dereferenced null pointer using operator[]",
	"Used (never initialized) dead pointer in an expression",
	"Used (already deleted) dead pointer in an expression",
	"Used (out of bounds) dead pointer in an expression",
	"Used (never initialized) dead pointer in a comparison",
	"Used (already deleted) dead pointer in a comparison",
	"Used (out of bounds) dead pointer in a comparison",
	"Used null pointer on only one side of an inequality comparison; if one side is null then the both sides must be null",
	"Both pointers being compared are alive but point into different memory blocks, so the comparison is undefined",
	"Used (never initialized) dead pointer in an arithmetic expression",
	"Used (already deleted) dead pointer in an arithmetic expression",
	"Used (out of bounds) dead pointer in an arithmetic expression",
	"Used null pointer in an arithmetic expression",
	"Used null pointer on only one side of a pointer subtraction expression; if one side is null then both sides must be null",
	"Both pointers being subtracted are alive but point into different memory blocks, so the distance between them is undefined",
	"Pointer arithmetic has moved a live pointer out of bounds",
	"Used operator[] on a pointer that does not point to an array",
	"Array index %d is out of bounds; valid indices are in the range [0..%lu]",
	"A previous operation has made this pointer invalid"
};

// ===========================================================================
/*
 * Messages corresponding to the warning codes used by Dereferee.
 */
static const char* warning_messages[] =
{
	"Memory leak caused by last live pointer to memory block going out of scope",
	"Memory leak caused by last live pointer to memory block being overwritten",
	"Memory %s allocated block was corrupted, likely due to invalid array indexing or pointer arithmetic"
};

// ===========================================================================
/*
 * Memory block corruption types.
 */
static const char* corruption_messages[] =
{
	"", "before", "after", "before and after"
};

// ===========================================================================
namespace DerefereeSupport
{

/**
 * Interface and implementation of the msvc_debugger_listener class.
 */
class msvc_debugger_listener : public Dereferee::listener
{
private:
	/**
	 * Stores the memory usage stats for the final report.
	 */
	const Dereferee::usage_stats* usage_stats;
	
	/**
	 * The prefix string to prepend to all lines output by the listener.
	 */
	char* prefix_string;

	/**
	 * The stream to output messages to if a debugger is not running.
	 */
	FILE* stream;

	/**
	 * The maximum number of leaks to output in the final report.
	 */
	size_t max_leaks;

	/**
	 * True if a debugger is present; otherwise, false.
	 */
	BOOL debugging;

	/**
	 * The platform under which Dereferee is running.
	 */
	Dereferee::platform* platform;

	// -----------------------------------------------------------------------
	/**
	 * Formats a string and outputs it to the debugger using
	 * OutputDebugString.
	 *
	 * @param format the printf-style format string
	 * @param args a varargs list containing the values to be formatted
	 */
	void debug_vprintf(const char* format, va_list args);

	// -----------------------------------------------------------------------
	/**
	 * Formats a string and outputs it, with the prefix string, to the
	 * listener's output destination.
	 *
	 * @param format the printf-style format string
	 * @param ... the values to be formatted
	 */
	void prefix_printf(const char* format, ...);

	// -----------------------------------------------------------------------
	/**
	 * Formats a string and outputs it, without the prefix string, to the
	 * listener's output destination.
	 *
	 * @param format the printf-style format string
	 * @param ... the values to be formatted
	 */
	void noprefix_printf(const char* format, ...);

	// -----------------------------------------------------------------------
	/**
	 * Formats a string and outputs it, without the prefix string, to the
	 * listener's output destination.
	 *
	 * @param format the printf-style format string
	 * @param args a varargs list containing the values to be formatted
	 */
	void noprefix_vprintf(const char* format, va_list args);

	// -----------------------------------------------------------------------
	/**
	 * Prints a backtrace to the output stream. Any Dereferee entries in the
	 * backtrace will be filtered out.
	 *
	 * @param backtrace the backtrace to be printed
	 * @param label a label to print before the first line in the backtrace
	 */
	void print_backtrace(void** backtrace, const char* label);

public:
	// -----------------------------------------------------------------------
	msvc_debugger_listener(const Dereferee::option* options,
		Dereferee::platform* platform);
	
	// -----------------------------------------------------------------------
	~msvc_debugger_listener();

	// -----------------------------------------------------------------------
	size_t maximum_leaks_to_report();

	// -----------------------------------------------------------------------
	void begin_report(const Dereferee::usage_stats& stats);

	// -----------------------------------------------------------------------
	void report_leak(const Dereferee::allocation_info& leak);
	
	// -----------------------------------------------------------------------
	void report_truncated(size_t reports_logged, size_t actual_leaks);
	
	// -----------------------------------------------------------------------
	void end_report();
	
	// -----------------------------------------------------------------------
	void error(Dereferee::error_code code, va_list args);

	// -----------------------------------------------------------------------
	void warning(Dereferee::warning_code code, va_list args);
};


// ---------------------------------------------------------------------------
msvc_debugger_listener::msvc_debugger_listener(
	const Dereferee::option* options, Dereferee::platform* platform)
{
	// Initialize defaults.
	this->platform = platform;
	stream = stdout;
	prefix_string = NULL;
	max_leaks = UINT_MAX;

	while(options->key != NULL)
	{
		if(strcmp(options->key, "use.stderr") == 0)
		{
			if(strcmp(options->value, "true") == 0)
			{
				stream = stderr;
			}
		}
		else if(strcmp(options->key, "output.prefix") == 0)
		{
			size_t len = strlen(options->value);
			prefix_string = (char*)malloc(len + 1);
			strncpy(prefix_string, options->value, len);
		}
		else if(strcmp(options->key, "max.leaks.to.report") == 0)
		{
			max_leaks = atoi(options->value);
		}
		
		options++;
	}

	// Determine if a debugger is currently present over this process. If so,
	// we send any output that we generate to the debugger via
	// OutputDebugString instead of stdout or stderr.
	debugging = IsDebuggerPresent();
}

// ---------------------------------------------------------------------------
msvc_debugger_listener::~msvc_debugger_listener()
{
	if(prefix_string)
		free(prefix_string);
}

// ------------------------------------------------------------------
size_t msvc_debugger_listener::maximum_leaks_to_report()
{
	return max_leaks;
}

// ------------------------------------------------------------------
void msvc_debugger_listener::begin_report(const Dereferee::usage_stats& stats)
{
	usage_stats = &stats;

	if(stats.leaks() > 0)
	{
		prefix_printf("%d memory leaks were detected:\n",
			   stats.leaks());
		prefix_printf("--------\n");
	}
	else
	{
		prefix_printf("No memory leaks detected.\n");
	}
}

// ------------------------------------------------------------------
void msvc_debugger_listener::report_leak(
	const Dereferee::allocation_info& leak)
{
	prefix_printf("Leaked %u bytes ", leak.block_size());

	if(leak.type_name())
	{
		char demangled[512] = { '\0' };
		strncpy(demangled, leak.type_name(), 512);

		if(leak.is_array())
		{
			if (leak.array_size())
			{
				noprefix_printf("(%s[%u]) ", demangled, leak.array_size());
			}
			else
			{
				noprefix_printf("(%s[]) ", demangled);
			}
		}
		else
		{
			noprefix_printf("(%s) ", demangled);
		}
	}
	
	noprefix_printf("at address %p\n", leak.address());

	print_backtrace(leak.backtrace(), "allocated in");

	prefix_printf("\n");
}		

// ------------------------------------------------------------------
void msvc_debugger_listener::report_truncated(size_t reports_logged,
											  size_t actual_leaks)
{
	prefix_printf("\n");
	prefix_printf("(only %u of %u leaks shown)\n",
		reports_logged, actual_leaks);
}

// ------------------------------------------------------------------
void msvc_debugger_listener::end_report()
{
	prefix_printf("\n");
	prefix_printf("Memory usage statistics:\n");
	prefix_printf("--------\n");
	prefix_printf("Total memory allocated during execution:   "
				   "%u bytes\n", usage_stats->total_bytes_allocated());
	prefix_printf("Maximum memory in use during execution:    "
				   "%u bytes\n", usage_stats->maximum_bytes_in_use());
	prefix_printf("Number of calls to new:                    %u\n",
				   usage_stats->calls_to_new());
	prefix_printf("Number of calls to delete (non-null):      %u\n",
				   usage_stats->calls_to_delete());
	prefix_printf("Number of calls to new[]:                  %u\n",
				   usage_stats->calls_to_array_new());
	prefix_printf("Number of calls to delete[] (non-null):    %u\n",
				   usage_stats->calls_to_array_delete());
	prefix_printf("Number of calls to delete (null):          %u\n",
				   usage_stats->calls_to_delete_null());
	prefix_printf("Number of calls to delete[] (null):        %u\n",
				   usage_stats->calls_to_array_delete_null());
}

// ------------------------------------------------------------------
void msvc_debugger_listener::error(Dereferee::error_code code, va_list args)
{
	prefix_printf("Pointer error: ");
	noprefix_vprintf(error_messages[code], args);
	noprefix_printf("\n");

	void** bt = platform->get_backtrace(NULL, NULL);
	print_backtrace(bt, "error in");
	prefix_printf("\n");
	
	void* addr = bt[3];
	platform->free_backtrace(bt);
	
	if(debugging)
	{
		int bufsize = vsnprintf(NULL, 0, error_messages[code], args) + 1;
		char* buffer = (char*)malloc(bufsize);
		vsnprintf(buffer, bufsize, error_messages[code], args);

		char function[DEREFEREE_MAX_FUNCTION_LEN] = { 0 };
		char filename[DEREFEREE_MAX_FILENAME_LEN] = { 0 };
		int line = 0;

		bool success = platform->get_backtrace_frame_info(addr,
			function, filename, &line);

		if(success)
		{
			if(1 == _CrtDbgReport(_CRT_ERROR, filename, line, _pgmptr,
				buffer))
			{
				_CrtDbgBreak();
			}
		}

		free(buffer);
	}
}

// ------------------------------------------------------------------
void msvc_debugger_listener::warning(Dereferee::warning_code code,
									 va_list args)
{
	prefix_printf("Pointer warning: ");

	if(code == Dereferee::warning_memory_boundary_corrupted)
	{
		Dereferee::memory_corruption_location loc =
			(Dereferee::memory_corruption_location)va_arg(args, int);

		noprefix_printf(warning_messages[code], corruption_messages[loc]);
	}
	else
	{
		noprefix_vprintf(warning_messages[code], args);
	}

	noprefix_printf("\n");

	void** bt = platform->get_backtrace(NULL, NULL);
	print_backtrace(bt, "warning in");
	prefix_printf("\n");
	platform->free_backtrace(bt);
}

// ---------------------------------------------------------------------------
void msvc_debugger_listener::debug_vprintf(const char* format, va_list args)
{
	int bufsize = vsnprintf(NULL, 0, format, args) + 1;
	char* buffer = (char*)malloc(bufsize);
	vsnprintf(buffer, bufsize, format, args);
	OutputDebugStringA(buffer);
	free(buffer);
}

// ---------------------------------------------------------------------------
void msvc_debugger_listener::prefix_printf(const char* format, ...)
{
	if(debugging)
	{
		if(prefix_string)
			OutputDebugStringA(prefix_string);

		va_list args;
		va_start(args, format);
		debug_vprintf(format, args);
		va_end(args);
	}
	else
	{
		if(prefix_string)
			fprintf(stream, prefix_string);

		va_list args;
		va_start(args, format);
		vfprintf(stream, format, args);	
		va_end(args);
	}
}

// ---------------------------------------------------------------------------
void msvc_debugger_listener::noprefix_printf(const char* format, ...)
{
	if(debugging)
	{
		va_list args;
		va_start(args, format);
		debug_vprintf(format, args);
		va_end(args);
	}
	else
	{
		va_list args;
		va_start(args, format);
		vfprintf(stream, format, args);	
		va_end(args);
	}
}

// ---------------------------------------------------------------------------
void msvc_debugger_listener::noprefix_vprintf(const char* format, va_list args)
{
	if(debugging)
		debug_vprintf(format, args);
	else
		vfprintf(stream, format, args);	
}

// ------------------------------------------------------------------
void msvc_debugger_listener::print_backtrace(void** backtrace,
	const char* label)
{
	if(backtrace == NULL)
		return;

	bool first = true;

	char function[DEREFEREE_MAX_FUNCTION_LEN] = { 0 };
	char filename[DEREFEREE_MAX_FILENAME_LEN] = { 0 };
	int line = 0;

	while(*backtrace)
	{
		void *addr = *backtrace;
		bool success = platform->get_backtrace_frame_info(addr,
			function, filename, &line);

		if(success && strstr(function, "Dereferee") != function)
		{
			if(first)
			{
				prefix_printf("%14s: ", label);
				first = false;
			}
			else
				prefix_printf("                ");

			if(line)
				printf("%s (%s:%d)\n", function, filename, line);
			else
				printf("%s\n", function);
				
			if (strcmp(function, "main") == 0)
				break;
		}
		
		backtrace++;
	}
}

} // end namespace DerefereeSupport

// ===========================================================================
/*
 * Implementation of the functions called by the Dereferee memory manager to
 * create and destroy the listener object.
 */

Dereferee::listener* Dereferee::create_listener(
	const Dereferee::option* options, Dereferee::platform* platform)
{
	return new DerefereeSupport::msvc_debugger_listener(options, platform);
}

void Dereferee::destroy_listener(Dereferee::listener* listener)
{
	delete listener;
}

// ===========================================================================
