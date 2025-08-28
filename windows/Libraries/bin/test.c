#include <windows.h>
#include <stdio.h>

int main()
{
    HMODULE h = LoadLibraryA("C:\\Users\\hites\\Documents\\Flutter Projects\\mssql_connection\\windows\\Libraries\\bin\\sybdb.dll");
    if (!h)
    {
        DWORD err = GetLastError();
        LPVOID msgBuf;
        FormatMessageA(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            NULL,
            err,
            MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
            (LPSTR)&msgBuf,
            0,
            NULL);
        printf("LoadLibrary failed with %lu: %s\n", err, (char *)msgBuf);
        LocalFree(msgBuf);
        return 1;
    }
    printf("sybdb.dll loaded OK\n");
    FreeLibrary(h);
    return 0;
}
