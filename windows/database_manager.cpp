#include "include/mssql_connection/database_manager.h"

// Helper function to convert UTF-8 std::string to std::wstring for Windows API
std::wstring ConvertUtf8ToWide(const std::string& str) {
    if (str.empty()) {
        return std::wstring();
    }
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

using namespace rapidjson;

DatabaseManager::DatabaseManager()
	: m_env(NULL), m_conn(NULL), m_stmt(NULL), m_isConnected(false) {}

DatabaseManager::~DatabaseManager() {
	if (m_isConnected) {
		disconnect();
	}
}

bool DatabaseManager::connect(const std::string& server, const std::string& database, const std::string& user, const std::string& password, const std::string& timeoutInSeconds) {
	try {
		// ODBC connection logic here
		SQLRETURN ret;

		ret = SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &m_env);
		if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
			std::string errorMsg = printError(SQL_HANDLE_ENV, m_env);
			throw DatabaseException(errorMsg);
		}

		ret = SQLSetEnvAttr(m_env, SQL_ATTR_ODBC_VERSION, (SQLPOINTER)SQL_OV_ODBC3, 0);
		if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
			std::string errorMsg = printError(SQL_HANDLE_ENV, m_env);
			throw DatabaseException(errorMsg);
		}

		ret = SQLAllocHandle(SQL_HANDLE_DBC, m_env, &m_conn);
		if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
			std::string errorMsg = printError(SQL_HANDLE_ENV, m_env);
			throw DatabaseException(errorMsg);
		}

        // Prepare connection string as wide string for Unicode support
        std::wstring wconnString = L"Driver={ODBC Driver 18 for SQL Server};Server=" +
                                   ConvertUtf8ToWide(server) +
                                   L";Database=" + ConvertUtf8ToWide(database) +
                                   L";UID=" + ConvertUtf8ToWide(user) +
                                   L";PWD=" + ConvertUtf8ToWide(password) +
                                   L";TrustServerCertificate=yes;Connection Timeout=" +
                                   ConvertUtf8ToWide(timeoutInSeconds) + L";";

		ret = SQLDriverConnectW(m_conn, NULL, (SQLWCHAR*)wconnString.c_str(), SQL_NTS, NULL, 0, NULL, SQL_DRIVER_NOPROMPT);
		if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
			m_isConnected = true;
			return true;
		}
		else {
			std::string errorMsg = printError(SQL_HANDLE_DBC, m_conn);
			SQLFreeHandle(SQL_HANDLE_DBC, m_conn);
			SQLFreeHandle(SQL_HANDLE_ENV, m_env);
			throw DatabaseException(errorMsg);
		}
	}
	catch (const DatabaseException& e) {
		throw e;
	}
	catch (...) {
		throw DatabaseException("An unknown error occurred in connect.");
	}
}

void DatabaseManager::disconnect() {
	try {
		if (m_isConnected) {
			SQLDisconnect(m_conn);
			SQLFreeHandle(SQL_HANDLE_DBC, m_conn);
			SQLFreeHandle(SQL_HANDLE_ENV, m_env);
			m_isConnected = false;
		}
	}
	catch (const DatabaseException& e) {
		throw e;
	}
	catch (...) {
		throw DatabaseException("An unknown error occurred in disconnect.");
	}
}

std::string DatabaseManager::getData(const std::string& query) {
	try {
		if (!m_isConnected) {
			throw DatabaseException("Not connected to the database.");
		}

		SQLRETURN ret;
		Document results(kArrayType);
		Document::AllocatorType& allocator = results.GetAllocator();

		// Allocate statement handle
		ret = SQLAllocHandle(SQL_HANDLE_STMT, m_conn, &m_stmt);
		if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
			std::string errorMsg = printError(SQL_HANDLE_STMT, m_stmt);
			SQLFreeHandle(SQL_HANDLE_STMT, m_stmt);
			throw DatabaseException(errorMsg);
		}

        // Execute SQL query
        std::wstring wquery = ConvertUtf8ToWide(query);
        ret = SQLExecDirectW(m_stmt, (SQLWCHAR*)wquery.c_str(), SQL_NTS);
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            std::string errorMsg = printError(SQL_HANDLE_STMT, m_stmt);
            SQLFreeHandle(SQL_HANDLE_STMT, m_stmt);
            throw DatabaseException(errorMsg);
        }

		SQLSMALLINT numCols;
		SQLNumResultCols(m_stmt, &numCols);

		// Fetch rows from the query result
		while (SQLFetch(m_stmt) == SQL_SUCCESS) {
			Value row(kObjectType);

			for (SQLSMALLINT i = 1; i <= numCols; ++i) {
				SQLWCHAR columnName[256];
				SQLSMALLINT sqlDataType;
				SQLLEN indicator;

				// Get column information
				SQLDescribeColW(m_stmt, i, columnName, sizeof(columnName), NULL, &sqlDataType, NULL, NULL, NULL);

				// Column name as string
				// Convert SQLWCHAR to std::wstring first
				std::wstring wideColumnName(reinterpret_cast<const wchar_t*>(columnName));

				// Convert std::wstring to std::string
				std::string narrowColumnName = convertSQLWCHARToString(columnName);

				Value columnNameValue;
				columnNameValue.SetString(narrowColumnName.c_str(), allocator);

				// Column value based on its type
				Value columnValue;
				switch (sqlDataType) {
				case SQL_INTEGER:
				case SQL_TINYINT:
				case SQL_SMALLINT:
				case SQL_BIT: {
					SQLINTEGER intValue;
					SQLGetData(m_stmt, i, SQL_INTEGER, &intValue, sizeof(intValue), &indicator);
					if (indicator != SQL_NULL_DATA) {
						columnValue.SetInt(intValue);
					}
					else {
						columnValue.SetNull();
					}
					break;
				}
				case SQL_FLOAT:
				case SQL_DECIMAL:
				case SQL_NUMERIC:
				case SQL_DOUBLE: {
					SQLDOUBLE doubleValue;
					SQLGetData(m_stmt, i, SQL_DOUBLE, &doubleValue, sizeof(doubleValue), &indicator);
					if (indicator != SQL_NULL_DATA) {
						columnValue.SetDouble(doubleValue);
					}
					else {
						columnValue.SetNull();
					}
					break;
				}
				default: {
					SQLWCHAR charValue[1024] = { 0 };
					SQLGetData(m_stmt, i, SQL_C_WCHAR, charValue, sizeof(charValue), &indicator);

					if (indicator != SQL_NULL_DATA) {
						std::string narrowCharValue = convertSQLWCHARToString(charValue);
						columnValue.SetString(narrowCharValue.c_str(), allocator);
					}
					else {
						columnValue.SetNull();
					}
					break;
				}
				}

				// Add column name-value pair to row object
				row.AddMember(columnNameValue, columnValue, allocator);
			}

			// Push row into the result array
			results.PushBack(row, allocator);
		}

		// Convert result into a string
		StringBuffer buffer;
		PrettyWriter<StringBuffer> writer(buffer);
		results.Accept(writer);

		SQLFreeHandle(SQL_HANDLE_STMT, m_stmt);
		return buffer.GetString();
	}
	catch (const DatabaseException& e) {
		throw e;
	}
	catch (...) {
		throw DatabaseException("An unknown error occurred in getData.");
	}
}

std::string convertSQLWCHARToString(const SQLWCHAR* sqlwcharArray) {
	if (sqlwcharArray == nullptr) {
		return "";
	}

    const wchar_t* wstr = reinterpret_cast<const wchar_t*>(sqlwcharArray);
    size_t wlen = wcslen(wstr);
    if (wlen == 0) {
        return "";
    }

    int bufferSize = WideCharToMultiByte(CP_UTF8, 0, wstr, static_cast<int>(wlen), nullptr, 0, nullptr, nullptr);
    if (bufferSize == 0) {
        return ""; // Error
    }

    std::string result(bufferSize, '\0');
    int converted = WideCharToMultiByte(CP_UTF8, 0, wstr, static_cast<int>(wlen), &result[0], bufferSize, nullptr, nullptr);
    if (converted == 0) {
        return ""; // Error
    }

	return result;
}

std::string DatabaseManager::writeData(const std::string& query) {
	try {
		if (!m_isConnected) {
			throw DatabaseException("Not connected to the database.");
		}

		SQLRETURN ret;

		// Allocate statement handle
		ret = SQLAllocHandle(SQL_HANDLE_STMT, m_conn, &m_stmt);
		if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
			std::string errorMsg = printError(SQL_HANDLE_STMT, m_stmt);
			SQLFreeHandle(SQL_HANDLE_STMT, m_stmt);
			throw DatabaseException(errorMsg);
		}

        // Execute SQL query
        std::wstring wquery = ConvertUtf8ToWide(query);
        ret = SQLExecDirectW(m_stmt, (SQLWCHAR*)wquery.c_str(), SQL_NTS);
        if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
            SQLLEN affectedRows;
            SQLRowCount(m_stmt, &affectedRows);

			SQLFreeHandle(SQL_HANDLE_STMT, m_stmt);

			// Returning affected rows in JSON format
			return "{ \"affectedRows\": " + std::to_string(affectedRows) + " }";
		}
		else {
			std::string errorMsg = printError(SQL_HANDLE_STMT, m_stmt);
			SQLFreeHandle(SQL_HANDLE_STMT, m_stmt);
			throw DatabaseException(errorMsg);
		}
	}
	catch (const DatabaseException& e) {
		throw e;
	}
	catch (...) {
		throw DatabaseException("An unknown error occurred in writeData.");
	}
}

std::string DatabaseManager::printError(SQLSMALLINT handleType, SQLHANDLE handle) {
	SQLWCHAR sqlState[SQL_SQLSTATE_SIZE + 1], message[SQL_MAX_MESSAGE_LENGTH];
	SQLINTEGER nativeError;
	SQLSMALLINT textLength;

	// Retrieve diagnostic record
	SQLRETURN ret = SQLGetDiagRecW(
		handleType,
		handle,
		1,
		sqlState,
		&nativeError,
		message,
		sizeof(message) / sizeof(SQLWCHAR),
		&textLength
	);

	if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
		return "Failed to retrieve error information";
	}

	// Convert wide character error message to string
	std::string errorMessage = convertSQLWCHARToString(message);
	std::string errorState = convertSQLWCHARToString(sqlState);

	// Construct detailed error message
	std::string fullErrorMessage =
		"SQL Error State: " + errorState +
		", Native Error Code: " + std::to_string(nativeError) +
		", Message: " + errorMessage;

	// Optional: Print to cerr for logging
	std::cerr << fullErrorMessage << std::endl;

	return fullErrorMessage;
}
