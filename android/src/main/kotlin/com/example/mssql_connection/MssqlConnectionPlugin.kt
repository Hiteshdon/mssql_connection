package com.example.mssql_connection

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.os.StrictMode;
import android.content.Context
import kotlinx.coroutines.launch

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.json.JSONArray

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Locale
import kotlin.time.ExperimentalTime
import kotlin.time.measureTime



class MssqlConnectionPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private lateinit var databaseManager: DatabaseManager
  private val mainScope = CoroutineScope(Dispatchers.Main)
  private var connection: Connection? = null
//  private val executorService = Executors.newSingleThreadExecutor()

  override fun onAttachedToEngine( binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel =
            MethodChannel(binding.binaryMessenger, "mssql_connection")
    channel.setMethodCallHandler(this)
    val policy = StrictMode.ThreadPolicy.Builder().permitAll().build()
    StrictMode.setThreadPolicy(policy)
    databaseManager = DatabaseManager()
  }

  override fun onDetachedFromEngine( binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
//    executorService.shutdown()
    try {
      if (connection != null) {
        connection!!.close()
      }
      databaseManager.disconnect()
    } catch (e: Exception) {
      e.printStackTrace()
    }
  }

  override fun onMethodCall( call: MethodCall,  result: Result) {
    CoroutineScope(Dispatchers.IO).launch {
      when (call.method) {
        "connect" -> connect(call, result)
        "getData" -> getData(call, result)
        "writeData" ->writeData(call, result)
        "disconnect" -> disconnect(result)
        else -> result.notImplemented()
      }
    }

  }

  private suspend fun connect(call: MethodCall, result: Result) {
    val url = call.argument<String>("url")
    val username = call.argument<String>("username")
    val password = call.argument<String>("password")
    val timeoutInSeconds = call.argument<Int>("timeoutInSeconds")
    withContext(Dispatchers.IO){
      try {
        databaseManager.connect(url!!, username!!, password!!, timeoutInSeconds!!)
        result.success(true)
      } catch (e: Exception) {
        Log.e("MssqlConnectionPlugin", "Error connecting to the database: $e")
        result.error("DATABASE_ERROR", e.message, null)
      }
    }
  }

//  @OptIn(ExperimentalTime::class)
  private suspend fun getData(call: MethodCall, result: Result) {
    val query = call.argument<String>("query")

    withContext(Dispatchers.IO) {
      try {
        //        val time = measureTime{
        val resultSet:List<String> = databaseManager.getData(query!!)
//        }
//        Log.i("MssqlConnectionPlugin", "Duration: $time GetData")
        result.success(resultSet);
      } catch (e: Exception) {
        Log.e("MssqlConnectionPlugin", "Error fetching data from the database: $e")
        result.error("DATABASE_ERROR", e.message, null)
      }
    }
  }

//  @OptIn(ExperimentalTime::class)
  private suspend fun writeData(call: MethodCall, result: Result) {
    val query = call.argument<String>("query")

    withContext(Dispatchers.IO) {
      try {
        val affectedRows:Int
//        val time = measureTime{
          affectedRows = databaseManager.writeData(query!!)
//        }
//        Log.i("MssqlConnectionPlugin", "Duration: $time WriteData")
        result.success(JSONObject().put("affectedRows" , affectedRows).toString())
      } catch (e: Exception) {
        Log.e("MssqlConnectionPlugin", "Error writing data to the database: $e")
        result.error("DATABASE_ERROR", e.message, null)
      }
    }
  }

  private suspend fun disconnect(result: Result) {
    withContext(Dispatchers.IO) {
      try {
        databaseManager.disconnect()
        result.success(true)
      } catch (e: Exception) {
        Log.e("MssqlConnectionPlugin", "Error disconnecting from the database: $e")
        result.error("DATABASE_ERROR", e.message, null)
      }
    }
  }

  @OptIn(ExperimentalTime::class)
  private fun resultSetToJsonArray(resultSet: ResultSet): String {
    val jsonArray = JSONArray()
    var time = measureTime {
    val metaData = resultSet.metaData
    while (resultSet.next()) {
      /*val jsonObject = JSONObject()
      for (i in 1..metaData.columnCount) {
        val columnName = metaData.getColumnName(i)
        val columnValue = resultSet.getObject(i)
        jsonObject.put(columnName, columnValue)
      }
      jsonArray.put(jsonObject)*/
      val metaData = resultSet.metaData
      val columnNames = (1..metaData.columnCount).map { metaData.getColumnName(it) }.toTypedArray()
      while (resultSet.next()) {
        val jsonObject = JSONObject()
        columnNames.forEachIndexed { i, columnName ->
          val columnValue = resultSet.getObject(columnName)
          jsonObject.put(columnName, columnValue)
        }
        jsonArray.put(jsonObject)
      }

    }
    }
    Log.i("MssqlConnectionPlugin", "Duration: $time")
    return jsonArray.toString()
  }


}