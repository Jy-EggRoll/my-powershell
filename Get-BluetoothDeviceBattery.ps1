$BatteryKey = "{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"
# $keyboard = Get-PnpDevice -FriendlyName "AKS068-*" | Select-Object DeviceID, Name
# $mouse = Get-PnpDevice -FriendlyName "*SC580*" | Select-Object DeviceID, Name
$bluetoothDevices = Get-PnpDevice -Class "Bluetooth" | Select-Object DeviceID, Name

# if ($keyboard.DeviceID) {
#     $powerStatus = Get-PnpDeviceProperty -InstanceId $keyboard.DeviceID -KeyName $BatteryKey
#     Write-Host "###########"
#     Write-Host "键盘：$($keyboard.Name)"
#     # Write-Host "ID：$($keyboard.DeviceID)"
#     Write-Host "电量：$($powerStatus.Data)"
#     Write-Host "###########"
# } else {
#     # Write-Host "未找到蓝牙键盘"
# }

# if ($mouse.DeviceID) {
#     $powerStatus = Get-PnpDeviceProperty -InstanceId $mouse.DeviceID -KeyName $BatteryKey
#     Write-Host "###########"
#     Write-Host "鼠标：$($mouse.Name)"
#     # Write-Host "ID：$($mouse.DeviceID)"
#     Write-Host "电量：$($powerStatus.Data)"
#     Write-Host "###########"
# } else {
#     # Write-Host "未找到蓝牙鼠标"
# }

foreach ($bluetoothDevice in $bluetoothDevices) {
    $powerStatus = Get-PnpDeviceProperty -InstanceId $bluetoothDevice.DeviceID -KeyName $BatteryKey
    if ($powerStatus.Data) {
        Write-Host "设备：$($bluetoothDevice.Name)"
        Write-Host "ID：$($bluetoothDevice.DeviceID)"
        Write-Host "电量：$($powerStatus.Data)"
    }
}