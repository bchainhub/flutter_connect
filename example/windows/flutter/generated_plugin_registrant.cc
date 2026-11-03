//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <app_links/app_links_plugin_c_api.h>
#include <bluetooth_low_energy_windows/bluetooth_low_energy_windows_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AppLinksPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AppLinksPluginCApi"));
  BluetoothLowEnergyWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("BluetoothLowEnergyWindowsPluginCApi"));
}
