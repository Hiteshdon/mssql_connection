#include "mssql_connection_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include "include/mssql_connection/database_manager.h"

namespace mssql_connection {

	// Static instance of DatabaseManager
	DatabaseManager databaseManager;

	// static
	void MssqlConnectionPlugin::RegisterWithRegistrar(
		flutter::PluginRegistrarWindows* registrar) {
		auto channel =
			std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
				registrar->messenger(), "mssql_connection/windows",
				&flutter::StandardMethodCodec::GetInstance());

		auto plugin = std::make_unique<MssqlConnectionPlugin>();

		channel->SetMethodCallHandler(
			[plugin_pointer = plugin.get()](const auto& call, auto result) {
				plugin_pointer->HandleMethodCall(call, std::move(result));
			});

		registrar->AddPlugin(std::move(plugin));
	}

	MssqlConnectionPlugin::MssqlConnectionPlugin() {}

	MssqlConnectionPlugin::~MssqlConnectionPlugin() {}

	void MssqlConnectionPlugin::HandleMethodCall(
		const flutter::MethodCall<flutter::EncodableValue>& method_call,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
		const auto& method_name = method_call.method_name();

		if (method_name == "connect") {
			try {
				const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
				if (args) {
					auto server = std::get<std::string>(args->at(flutter::EncodableValue("server")));
					auto database = std::get<std::string>(args->at(flutter::EncodableValue("database")));
					auto user = std::get<std::string>(args->at(flutter::EncodableValue("user")));
					auto password = std::get<std::string>(args->at(flutter::EncodableValue("password")));
					auto timeout = std::get<std::string>(args->at(flutter::EncodableValue("timeout")));

					bool connected = databaseManager.connect(server, database, user, password, timeout);
					result->Success(flutter::EncodableValue(connected));
				}
				else {
					result->Error("Invalid Arguments", "Expected a map with connection parameters.");
				}
			}
			catch (const DatabaseException& e) {
				result->Error("DATABASE_ERROR", e.what());
			}
			catch (const std::exception& e) {
				result->Error("UNKNOWN_ERROR", e.what());
			}
			catch (...) {
				result->Error("UNKNOWN_ERROR", "An unknown error occurred during connect.");
			}
		}
		else if (method_name == "disconnect") {
			try {
				databaseManager.disconnect();
				result->Success(flutter::EncodableValue(true));
			}
			catch (const DatabaseException& e) {
				result->Error("DATABASE_ERROR", e.what());
			}
			catch (const std::exception& e) {
				result->Error("UNKNOWN_ERROR", e.what());
			}
			catch (...) {
				result->Error("UNKNOWN_ERROR", "An unknown error occurred during disconnect.");
			}
		}
		else if (method_name == "getData") {
			try {
				const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
				if (args) {
					auto query = std::get<std::string>(args->at(flutter::EncodableValue("query")));

					std::string data = databaseManager.getData(query);
					result->Success(flutter::EncodableValue(data));
				}
				else {
					result->Error("Invalid Arguments", "Expected a map with query.");
				}
			}
			catch (const DatabaseException& e) {
				result->Error("DATABASE_ERROR", e.what());
			}
			catch (const std::exception& e) {
				result->Error("UNKNOWN_ERROR", e.what());
			}
			catch (...) {
				result->Error("UNKNOWN_ERROR", "An unknown error occurred during getData.");
			}
		}
		else if (method_name == "writeData") {
			try {
				const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
				if (args) {
					auto query = std::get<std::string>(args->at(flutter::EncodableValue("query")));

					std::string response = databaseManager.writeData(query);
					result->Success(flutter::EncodableValue(response));
				}
				else {
					result->Error("Invalid Arguments", "Expected a map with query.");
				}
			}
			catch (const DatabaseException& e) {
				result->Error("DATABASE_ERROR", e.what());
			}
			catch (const std::exception& e) {
				result->Error("UNKNOWN_ERROR", e.what());
			}
			catch (...) {
				result->Error("UNKNOWN_ERROR", "An unknown error occurred during writeData.");
			}
		}
		else if (method_name == "executeParameterizedQuery") {
			try {
				const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
				if (args) {
					auto sql = std::get<std::string>(args->at(flutter::EncodableValue("sql")));
					
					// Extract parameters list
					std::vector<std::string> params;
					const auto* params_list = std::get_if<flutter::EncodableList>(
						&args->at(flutter::EncodableValue("params"))
					);
					
					if (params_list) {
						for (const auto& param : *params_list) {
							params.push_back(std::get<std::string>(param));
						}
					}

					std::string response = databaseManager.executeParameterizedQuery(sql, params);
					result->Success(flutter::EncodableValue(response));
				}
				else {
					result->Error("Invalid Arguments", "Expected a map with sql and params.");
				}
			}
			catch (const DatabaseException& e) {
				result->Error("DATABASE_ERROR", e.what());
			}
			catch (const std::exception& e) {
				result->Error("UNKNOWN_ERROR", e.what());
			}
			catch (...) {
				result->Error("UNKNOWN_ERROR", "An unknown error occurred during executeParameterizedQuery.");
			}
		}
		else {
			result->NotImplemented();
		}

	}

}