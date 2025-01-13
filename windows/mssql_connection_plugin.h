#ifndef FLUTTER_PLUGIN_MSSQL_CONNECTION_PLUGIN_H_
#define FLUTTER_PLUGIN_MSSQL_CONNECTION_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace mssql_connection {

class MssqlConnectionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  MssqlConnectionPlugin();

  virtual ~MssqlConnectionPlugin();

  // Disallow copy and assign.
  MssqlConnectionPlugin(const MssqlConnectionPlugin&) = delete;
  MssqlConnectionPlugin& operator=(const MssqlConnectionPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace mssql_connection

#endif  // FLUTTER_PLUGIN_MSSQL_CONNECTION_PLUGIN_H_
