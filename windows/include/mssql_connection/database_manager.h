#pragma once

#include <windows.h>   // Essential for Windows data types and definitions
#include <sql.h>       // Core ODBC definitions
#include <sqlext.h>    // Extended ODBC definitions
#include "include/external/msodbcsql.h" // Microsoft-specific ODBC extensions
#include <chrono>      // For time measurement
#include <iostream>    // For standard input/output
#include <fstream>     // For reading config file
#include <string>
#include <vector>      // For std::vector

// RapidJSON headers
#include "include/external/rapidjson/document.h"    // For parsing JSON data
#include "include/external/rapidjson/reader.h"      // For advanced parsing (optional)
#include "include/external/rapidjson/writer.h"      // For writing to JSON (optional)
#include "include/external/rapidjson/stringbuffer.h" // For handling JSON output buffer
#include "include/external/rapidjson/prettywriter.h" // For pretty JSON output


class DatabaseException : public std::exception {
public:
    DatabaseException(const std::string& message) : message_(message) {}

    const char* what() const noexcept override {
        return message_.c_str();
    }

private:
    std::string message_;
};

class DatabaseManager {
public:
    // Constructor and Destructor
    DatabaseManager();
    ~DatabaseManager();

    // Connect to the database
    bool connect(const std::string& server, const std::string& database, const std::string& user, const std::string& password, const std::string& timeoutInSeconds);

    // Disconnect from the database
    void disconnect();

    // Fetch data from the database
    std::string getData(const std::string& query);

    // Write data to the database
    std::string writeData(const std::string& query);

    // Execute parameterized query with prepared statements
    std::string executeParameterizedQuery(const std::string& sql, const std::vector<std::string>& params);

    // Error handling
    std::string printError(SQLSMALLINT handleType, SQLHANDLE handle);

private:
    SQLHENV m_env;      // Environment handle for ODBC
    SQLHDBC m_conn;     // Connection handle for ODBC
    SQLHSTMT m_stmt;    // Statement handle for SQL commands
    bool m_isConnected; // Flag to check connection status
};

std::string convertSQLWCHARToString(const SQLWCHAR* sqlwcharArray);

// Helper function to convert UTF-8 std::string to std::wstring for Windows API
std::wstring ConvertUtf8ToWide(const std::string& str);
