#include "include/mssql_connection/mssql_connection_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "mssql_connection_plugin.h"

void MssqlConnectionPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  mssql_connection::MssqlConnectionPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
