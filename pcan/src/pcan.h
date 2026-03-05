#include <stdint.h>


// Define __stdcall for non-Windows platforms
#ifndef _WIN32
#define __stdcall
#endif

typedef uint8_t  BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;
typedef uint64_t UINT64;
typedef char*    LPSTR;

#define __T(x)  x


#include "PCANBasic.h"