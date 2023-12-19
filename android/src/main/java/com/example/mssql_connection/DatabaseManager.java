package com.example.mssql_connection;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import android.util.Log;

public class DatabaseManager {

    private String url;
    private String username;
    private String password;
    private Connection connection;
    private int timeoutInSeconds;

    private void establishConnection() throws SQLException, ClassNotFoundException {
        try {
            Log.i("DatabaseManager", "Establishing database connection...");
            Class.forName("net.sourceforge.jtds.jdbc.Driver");
            DriverManager.setLoginTimeout(timeoutInSeconds);
            connection = DriverManager.getConnection(url, username, password);
            Log.i("DatabaseManager", "Database connection established successfully.");
        } catch (ClassNotFoundException | SQLException e) {
            Log.e("DatabaseManager", "Error establishing database connection: " + e.getMessage());
            throw e;
        }
    }

    private void reconnectIfNecessary() throws SQLException, ClassNotFoundException {
        try {
            if (connection == null || connection.isClosed()) {
                establishConnection();
            }
        } catch (SQLException e) {
            Log.e("DatabaseManager", "Error checking connection status: " + e.getMessage());
            throw e;
        }
    }

    public void connect(String url, String username, String password, int timeoutInSeconds)
            throws SQLException, ClassNotFoundException {
        this.url = url;
        this.username = username;
        this.password = password;
        this.timeoutInSeconds = timeoutInSeconds;
        reconnectIfNecessary();
    }

    public ResultSet getData(String query) throws SQLException, ClassNotFoundException {
        reconnectIfNecessary();
        ResultSet resultSet = null;
        try {
            final Statement statement = connection.createStatement();
            resultSet = statement.executeQuery(query);
        } catch (SQLException e) {
            if (isConnectionException(e)) {
                // Attempt to reconnect and retry the operation
                Log.i("DatabaseManager", "Connection lost. Reconnecting and retrying operation...");
                reconnectIfNecessary();
                try {
                    final Statement statement = connection.createStatement();
                    resultSet = statement.executeQuery(query);
                } catch (SQLException e1) {
                    Log.e("DatabaseManager", "Error retrying query: " + e1.getMessage());
                    throw e1;
                }
            } else {
                Log.e("DatabaseManager", "Error executing query: " + e.getMessage());
                throw e;
            }
        }
        return resultSet;
    }

    public int writeData(String query) throws SQLException, ClassNotFoundException {
        reconnectIfNecessary();
        int affectedRows = 0;
        try {
            final PreparedStatement statement = connection.prepareStatement(query);
            affectedRows = statement.executeUpdate();
        } catch (SQLException e) {
            if (isConnectionException(e)) {
                // Attempt to reconnect and retry the operation
                Log.i("DatabaseManager", "Connection lost. Reconnecting and retrying operation...");
                reconnectIfNecessary();
                try {
                    final PreparedStatement statement = connection.prepareStatement(query);
                    affectedRows = statement.executeUpdate();
                } catch (SQLException e1) {
                    Log.e("DatabaseManager", "Error retrying update: " + e1.getMessage());
                    throw e1;
                }
            } else {
                Log.e("DatabaseManager", "Error executing update: " + e.getMessage());
                throw e;
            }
        }
        return affectedRows;
    }

    public void disconnect() throws SQLException {
        try {
            if (connection != null) {
                connection.close();
            }
            Log.i("DatabaseManager", "Disconnected from the database.");
        } catch (SQLException e) {
            Log.e("DatabaseManager", "Error disconnecting from the database: " + e.getMessage());
            throw e;
        }
    }

    private boolean isConnectionException(SQLException e) {
        return "08S01".equals(e.getSQLState()) || "08003".equals(e.getSQLState()) || "08007".equals(e.getSQLState());
    }
}
