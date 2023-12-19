package com.example.mssql_connection;

import androidx.annotation.*;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.*;
import io.flutter.plugin.common.MethodChannel.*;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import com.example.mssql_connection.DatabaseManager;
import android.util.Log;

import org.json.*;

/** MssqlConnectionPlugin */
public class MssqlConnectionPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String CHANNEL_NAME = "mssql_connection";
    private DatabaseManager databaseManager;
    private MethodChannel channel;
    private static final ExecutorService executorService = Executors.newSingleThreadExecutor();

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), MssqlConnectionPlugin.CHANNEL_NAME);
        databaseManager = new DatabaseManager();
        channel.setMethodCallHandler(this);
    }

    @Deprecated
    public void registerWith(PluginRegistry.Registrar registrar) {
        channel = new MethodChannel(registrar.messenger(), MssqlConnectionPlugin.CHANNEL_NAME);
        databaseManager = new DatabaseManager();
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        try {
            databaseManager.disconnect();
        } catch (Exception e) {
            e.printStackTrace();
        }
        channel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "connect":
                executorService.execute(() -> {
                    try {
                        String url = call.argument("url");
                        String username = call.argument("username");
                        String password = call.argument("password");
                        int timeoutInSeconds = call.argument("timeoutInSeconds");

                        databaseManager.connect(url, username, password, timeoutInSeconds);
                        result.success(true);
                    } catch (Exception e) {
                        Log.e("MssqlConnectionPlugin", "Error connecting to the database: " + e);
                        result.error("DATABASE_ERROR", e.getMessage(), null);
                    }
                });
                break;
            case "getData":
                executorService.execute(() -> {
                    try {

                        String query = call.argument("query");
                        ResultSet resultSet = databaseManager.getData(query);
                        JSONArray jsonArray = resultSetToJsonArray(resultSet);
                        
                        result.success(jsonArray.toString());
                    } catch (Exception e) {
                        Log.e("MssqlConnectionPlugin", "Error fetching data from the database: " + e);
                        result.error("DATABASE_ERROR", e.getMessage(), null);
                    }
                });
                break;
            case "writeData":
                executorService.execute(() -> {
                    try {

                        String query = call.argument("query");
                        int affectedRows = databaseManager.writeData(query);
                        
                        JSONObject jsonObject = new JSONObject();
                        jsonObject.put("affectedRows", affectedRows);
                        result.success(jsonObject.toString());
                    } catch (Exception e) {
                        Log.e("MssqlConnectionPlugin", "Error writing data to the database: " + e);
                        result.error("DATABASE_ERROR", e.getMessage(), null);
                    }
                });
                break;
            case "disconnect":
                executorService.execute(() -> {
                    try {
                        databaseManager.disconnect();
                        result.success(true);
                    } catch (Exception e) {
                        Log.e("MssqlConnectionPlugin", "Error disconnecting from the database: " + e);
                        result.error("DATABASE_ERROR", e.getMessage(), null);
                    }
                });
                break;
            default:
                result.notImplemented();
        }
    }

    private JSONArray resultSetToJsonArray(ResultSet resultSet) throws SQLException, JSONException {
        JSONArray jsonArray = new JSONArray();
        while (resultSet.next()) {
            JSONObject jsonObject = new JSONObject();
            int columns = resultSet.getMetaData().getColumnCount();
            for (int i = 1; i <= columns; i++) {
                jsonObject.put(resultSet.getMetaData().getColumnName(i), resultSet.getObject(i));
            }
            jsonArray.put(jsonObject);
        }
        return jsonArray;
    }
}

