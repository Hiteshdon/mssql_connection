package com.example.mssql_connection

import android.util.Log
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.module.SimpleModule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.lang.StringBuilder
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.sql.SQLException
import java.sql.Statement


class DatabaseManager {
    private var connection: Connection? = null
    private var url: String? = null
    private var username: String? = null
    private var password: String? = null
    private var timeoutInSeconds: Int = 0

    private suspend fun establishConnection() {
        withContext(Dispatchers.IO) {
            try {
//                Log.i("DatabaseManager", "Establishing database connection...")
                Class.forName("net.sourceforge.jtds.jdbc.Driver")
                DriverManager.setLoginTimeout(timeoutInSeconds)
                connection = DriverManager.getConnection(url!!, username!!, password!!)
//                Log.i("DatabaseManager", "Database connection established successfully.")
            } catch (e: ClassNotFoundException) {
                Log.e("DatabaseManager", "Error establishing database connection: ${e.message}")
                throw e
            } catch (e: SQLException) {
                Log.e("DatabaseManager", "Error establishing database connection: ${e.message}")
                throw e
            }
        }
    }

    private suspend fun reconnectIfNecessary(forceEstablish: Boolean = false) {
        withContext(Dispatchers.IO) {
            try {
                if ((connection == null || connection!!.isClosed) || forceEstablish) {
                    establishConnection()
                }
            } catch (e: SQLException) {
                Log.e("DatabaseManager", "Error checking connection status: ${e.message}")
                throw e
            } catch (e: ClassNotFoundException) {
                Log.e("DatabaseManager", "Error checking connection status: ${e.message}")
                throw e
            }
        }
    }

    suspend fun connect(url: String, username: String, password: String, timeoutInSeconds: Int) {
        this.url = url
        this.username = username
        this.password = password
        this.timeoutInSeconds = timeoutInSeconds
        reconnectIfNecessary(true)
    }

    suspend fun getData(query: String): List<String> {
        reconnectIfNecessary()
        return withContext(Dispatchers.IO) {
            try {
                val statement = connection!!.createStatement(
                    ResultSet.TYPE_SCROLL_INSENSITIVE,
                    ResultSet.CONCUR_READ_ONLY
                )
                val result = statement.executeQuery(query)
                result.last()
                val totalSize = result.row;
                var chunkSize: Int = 1000
                result.beforeFirst();

                if (chunkSize < (totalSize / 10)) {
                    chunkSize = totalSize / 10
                }
                if(chunkSize>10000){
                    chunkSize =10000;
                }

                val chunks = (0..totalSize step chunkSize).map {
                    async{ readChunkedResult(query, it, chunkSize) }
                }
                val strings = chunks.awaitAll()
                strings
            } catch (e: SQLException) {
                if (isConnectionException(e)) {
                    getData(query)
                } else {
                    Log.e("DatabaseManager", "Error executing query: ${e.message}")
                    throw e
                }
            }
        }
    }

    private suspend fun readChunkedResult(query: String, startRow: Int, chunkSize: Int): String {
        try {
            return withContext(Dispatchers.IO) {
                var statement = connection!!.createStatement(
                    ResultSet.TYPE_SCROLL_SENSITIVE,
                    ResultSet.CONCUR_READ_ONLY
                )
                val result = statement.executeQuery(query);
                result.absolute(startRow)
                val module = SimpleModule()
                module.addSerializer(ResultSetSerializer(chunkSize))
                val objectMapper = ObjectMapper()
                objectMapper.registerModule(module)
                val objectNode = objectMapper.createObjectNode()
                objectNode.putPOJO("results", result);
                val jsonString = objectMapper.writeValueAsString(objectNode)
                result.close()
                statement.close()
                jsonString.substring(jsonString.indexOf("[") + 1, jsonString.lastIndexOf("]"))
            }
        } catch (e: SQLException) {
            if (isConnectionException(e)) {
                reconnectIfNecessary()
                readChunkedResult(query, startRow, chunkSize)
            }
            Log.e("DatabaseManager", "Error executing query: ${e.sqlState} | ${e.message}")
            throw e
        }
    }

    suspend fun writeData(query: String): Int {
        reconnectIfNecessary()
        return withContext(Dispatchers.IO) {
            try {
                val statement = connection!!.prepareStatement(query)
                statement.executeUpdate()
            } catch (e: SQLException) {
                if (isConnectionException(e)) {

                    reconnectIfNecessary()
                    writeData(query);
                } else {
                    Log.e("DatabaseManager", "Error executing update: ${e.message}")
                    throw e
                }
            }
        }
    }

    fun disconnect() {
        try {
            connection?.close()
//            Log.i("DatabaseManager", "Disconnected from the database.")
        } catch (e: SQLException) {
            Log.e("DatabaseManager", "Error disconnecting from the database: ${e.message}")
            throw e
        }
    }

    private fun isConnectionException(e: SQLException): Boolean {
        return "08S01" == e.sqlState || "08003" == e.sqlState || "08007" == e.sqlState || "HY010" == e.sqlState
    }
}