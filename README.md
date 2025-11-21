# PowerShell 功能集成

## 重要说明

此仓库处于暂停维护状态。

## 介绍

这是一个由我自己编写的 PowerShell 脚本集，用于实现一些常用功能，如电池健康度监测、功率监测、清理指定 PowerShell 历史记录、创建软硬链接等。

> [!TIP]
>
> 该仓库的所有功能均在向 Go 语言迁移，日后将发布实现同等功能或更强功能的跨平台实现版本。
>
> - 电池管理迁移进度 90%
> - 软硬链接迁移进度 - 已完成
> - 历史记录清理 - 未开始

## 发布说明

我更推荐您直接运行 PowerShell 脚本，即下载 Release 中的源代码，这保证了最佳的兼容性和灵活性。

不过，我仍然保留构建 exe 可执行文件的功能，并将其发布在 Release 中，供有需要的用户下载使用。这是由于如果您未安装 PowerShell7 环境，直接运行 ps1 脚本是会被禁止的（除非您修改执行策略），这为用户带来了额外的障碍。

> [!WARNING]
>
> v0 版本全部不稳定，仅作发布测试，请勿下载使用。
>
> ARM64 版本的实际架构仍为 x64，但是打包环境是 Windows on ARM，这可能会提升一些兼容性。如果您追求在 ARM 设备上运行的原生性，那么请用原生的 PowerShell 运行 ps1 脚本。

## 使用方法

### PowerShell7 用户

如果您的电脑上安装有 PowerShell7，那么使用 ps1 脚本是最好的选择。用法如下：

进入脚本所在目录，在该目录打开 PowerShell7，运行：

```powershell
.\Get-BatteryInfo.ps1  # 获取电池信息：设计容量、实际容量、健康度、电量
.\Get-BatteryInfo.ps1 -Monitor  # 实时监测功率
.\Get-BatteryInfo.ps1 -Bluetooth  # 获取已连接的蓝牙设备的电量
.\Get-BatteryInfo.ps1 -RefreshBluetoothCache  # 刷新已配对的蓝牙设备的缓存文件

.\Clear-SpecifiedHistory.ps1 -Like ""  # 清理指定 PowerShell 历史记录，使用 * 匹配
```

### PowerShell5 用户

如果您不想修改 PowerShell5 的脚本执行策略，请下载相应架构的 exe 可执行文件，在命令行中运行。用法如下：

进入 exe 所在目录，在该目录打开命令行，运行：

```powershell
.\Get-BatteryInfo-x64.exe  # 获取电池信息：设计容量、实际容量、健康度、电量
.\Get-BatteryInfo-x64.exe -Monitor  # 实时监测功率
.\Get-BatteryInfo-x64.exe -Bluetooth  # 获取已连接的蓝牙设备
.\Get-BatteryInfo-x64.exe -RefreshBluetoothCache  # 刷新已配对的蓝牙设备的缓存文件

.\Clear-SpecifiedHistory-x64.exe -Like ""  # 清理指定 PowerShell 历史记录，使用 * 匹配
```

如果您不愿在命令行中输入文件名，可以考虑创建快捷方式。如果您使用快捷方式运行 exe 文件时出现了运行结束后窗口马上退出的问题，请在快捷方式绑定的命令后面加上 `-wait` 参数，这样就可以通过双击来运行对应的文件了。

## 建议

文件名较长，您可以设置 PowerShell 别名。
