param(
    [switch]$Monitor,
    [switch]$Bluetooth,
    [switch]$BluetoothMonitor,
    [switch]$RefreshBluetoothCache
)

# 蓝牙相关常量和配置
$BatteryKey = "{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"
$IsConnectedKey = "{83DA6326-97A6-4088-9453-A1923F573B29} 15"
$CacheFilePath = "~\BluetoothDeviceIDCache.txt"

# 获取电池容量信息
function Get-BatteryCapacityInfo {
    # 生成电池报告
    Write-Host "正在矫正容量信息，请稍等" -ForegroundColor Yellow
    powercfg /batteryreport | Out-Null

    $reportPath = "battery-report.html"
    if (-not (Test-Path $reportPath)) {
        Write-Error "没有找到报告文件: $reportPath"
        return $null
    }

    # 读取报告内容
    $reportContent = Get-Content $reportPath -Raw

    # 定义正则表达式模式提取所需值
    $designCapacityPattern = '<span class="label">DESIGN CAPACITY</span></td><td>([\d,]+) mWh'
    $fullChargeCapacityPattern = '<span class="label">FULL CHARGE CAPACITY</span></td><td>([\d,]+) mWh'

    # 提取设计容量并转换为数字
    $designCapacity = $null
    if ($reportContent -match $designCapacityPattern) {
        $designCapacity = [int]($matches[1] -replace ',', '')
    }

    # 提取完全充电容量并转换为数字
    $fullChargeCapacity = $null
    if ($reportContent -match $fullChargeCapacityPattern) {
        $fullChargeCapacity = [int]($matches[1] -replace ',', '')
    }

    # 删除报告文件
    Remove-Item $reportPath -ErrorAction SilentlyContinue

    return @{
        DesignCapacity     = $designCapacity
        FullChargeCapacity = $fullChargeCapacity
    }
}

# 获取当前电量百分比
function Get-CurrentBatteryCharge {
    return (Get-CimInstance -ClassName Win32_Battery).EstimatedChargeRemaining
}

# 初始化监控状态
function Initialize-MonitorState {
    param($FullChargeCapacity)
    
    $currentCharge = Get-CurrentBatteryCharge
    $energyPerPercent = $FullChargeCapacity / 100
    
    return @{
        LastChargePercent = $currentCharge
        LastTimestamp     = Get-Date
        EnergyPerPercent  = $energyPerPercent
        IsInitialized     = $true
    }
}

# 检测电量是否变化
function Test-ChargeChange {
    param($CurrentCharge, $LastChargePercent)
    
    return $CurrentCharge -ne $LastChargePercent
}

# 计算功率（仅在电量变化时调用）
function Get-BatteryPower {
    param($CurrentCharge, $MonitorState)
    
    $chargeChange = $CurrentCharge - $MonitorState.LastChargePercent
    $timeElapsed = (Get-Date) - $MonitorState.LastTimestamp
    $timeElapsedHours = $timeElapsed.TotalSeconds / 3600
    $energyChange = $chargeChange * $MonitorState.EnergyPerPercent  # mWh
    $power = $energyChange / $timeElapsedHours  # mW
    $powerWatts = $power / 1000  # W
    
    return $powerWatts
}

# 计算电池耗尽或充满时间
function Get-BatteryTimeEstimate {
    param($CurrentCharge, $PowerWatts, $FullChargeCapacity)
    
    if ($PowerWatts -gt 0) {
        # 充电中 - 计算充满时间
        $remainingCapacity = (100 - $CurrentCharge) * ($FullChargeCapacity / 100)  # mWh
        $timeToFullHours = $remainingCapacity / ($PowerWatts * 1000)  # 小时
    }
    else {
        # 放电中 - 计算耗尽时间
        $remainingCapacity = $CurrentCharge * ($FullChargeCapacity / 100)  # mWh
        $timeToEmptyHours = $remainingCapacity / ([math]::Abs($PowerWatts) * 1000)  # 小时
        $timeToFullHours = $timeToEmptyHours
    }
    
    # 计算未来时间
    $currentTime = Get-Date
    $futureTime = $currentTime.AddHours($timeToFullHours)
    $futureHour = $futureTime.Hour
    $futureMinute = $futureTime.Minute
    $futureDay = $futureTime.Day
    $futureMonth = $futureTime.Month
    
    return "{0:D2} 月 {1:D2} 日 {2:D2}:{3:D2}" -f $futureMonth, $futureDay, $futureHour, $futureMinute
}

# 带颜色输出
function Write-ColoredOutput {
    param($CurrentCharge, $PowerWatts, $FullChargeCapacity)
    
    $powerSign = if ($PowerWatts -gt 0) { "+" } else { "" }
    $powerFormatted = "{0}{1:F2}" -f $powerSign, $PowerWatts
    
    if ($PowerWatts -gt 0) {
        $status = "充电中"
        $color = "Green"
    }
    else {
        $status = "放电中"
        $color = "Red"
    }
    
    $message = "当前电量 {0}%，{1}，功率 {2} W" -f $CurrentCharge, $status, $powerFormatted
    
    # 获取时间预测
    $timeEstimate = Get-BatteryTimeEstimate -CurrentCharge $CurrentCharge -PowerWatts $PowerWatts -FullChargeCapacity $FullChargeCapacity
    
    # 添加时间预测字符串
    if ($timeEstimate) {
        if ($PowerWatts -gt 0) {
            $message += "，若保持此功率，电量将于 {0} 充满" -f $timeEstimate
        }
        else {
            $message += "，若保持此功率，电量将于 {0} 耗尽" -f $timeEstimate
        }
    }
    
    Write-Host $message -ForegroundColor $color
}

function Request-UserConsent {
    Write-Host "请注意：蓝牙设备电量往往是不准确的，这大大依赖于设备本身的支持情况，仅可以作为参考。" -ForegroundColor Red
    Write-Host "未检测到缓存文件。" -ForegroundColor Yellow
    Write-Host "为了提高查询速度，建议缓存有电量信息的蓝牙设备。" -ForegroundColor Yellow
    Write-Host "这将显著减少之后每次查询的时间，避免扫描所有蓝牙设备。" -ForegroundColor Yellow
    Write-Host "缓存文件将被创建在 $CacheFilePath。" -ForegroundColor Yellow
    Write-Host "如果您同意创建缓存文件，请输入 y 并按回车；否则输入 n。" -ForegroundColor Yellow
    Write-Host "如果您不使用缓存，电量检测仍然可以正常运行，只是速度会较慢。" -ForegroundColor Yellow
    $response = Read-Host "是否创建缓存文件？(y/n)"
    return $response -match "^[Yy]"
}

function Show-BluetoothCacheNotice {
    Write-Host "请注意：蓝牙设备电量往往是不准确的，这大大依赖于设备本身的支持情况，仅可以作为参考。" -ForegroundColor Red
    Write-Host "提示：正在使用蓝牙设备缓存加速查询。" -ForegroundColor Green
    Write-Host "当蓝牙设备状态有更新时（比如重新配对了某个设备），请单独使用 -RefreshBluetoothCache 参数刷新缓存。" -ForegroundColor Yellow
}

function Write-BluetoothCache {
    param($Device)
    
    try {
        # 追加写入缓存文件
        "$($Device.DeviceID),$($Device.Name)" | Out-File -FilePath $CacheFilePath -Append -Encoding UTF8
    }
    catch {
        Write-Warning "无法写入缓存文件: $_"
    }
}

if ($Bluetooth) {
    # 检查缓存文件，不存在则询问用户是否创建
    $isApproved = $false
    if (-not (Test-Path $CacheFilePath)) {
        $bluetoothDevices = Get-PnpDevice -Class "Bluetooth" | Select-Object DeviceID, Name
        $isApproved = Request-UserConsent
        foreach ($bluetoothDevice in $bluetoothDevices) {
            $powerStatus = Get-PnpDeviceProperty -InstanceId $bluetoothDevice.DeviceID -KeyName $BatteryKey
            $isConnected = Get-PnpDeviceProperty -InstanceId $bluetoothDevice.DeviceID -KeyName $IsConnectedKey
            if ($powerStatus.Data -and $isConnected.Data) {
                Write-Host "---"
                Write-Host "设备：$($bluetoothDevice.Name)" -ForegroundColor Blue
                Write-Host "电量：$($powerStatus.Data)%"
                if ($isApproved) {
                    Write-BluetoothCache -Device $bluetoothDevice
                }
            }
        }
    }
    else {
        Show-BluetoothCacheNotice

        # 读取缓存文件，直接查询缓存中的设备
        $bluetoothDevices = @{}
        Get-Content -Path $CacheFilePath | ForEach-Object {
            $parts = $_ -split ","
            if ($parts.Count -eq 2) {
                $bluetoothDevices[$parts[0]] = $parts[1]
            }
        }
        foreach ($deviceId in $bluetoothDevices.Keys) {
            $powerStatus = Get-PnpDeviceProperty -InstanceId $deviceId -KeyName $BatteryKey
            $isConnected = Get-PnpDeviceProperty -InstanceId $deviceId -KeyName $IsConnectedKey
            if ($powerStatus.Data -and $isConnected.Data) {
                Write-Host "---"
                Write-Host "设备：$($bluetoothDevices[$deviceId])" -ForegroundColor Blue
                Write-Host "电量：$($powerStatus.Data)%"
            }
        }
    }
    exit 0
}

if ($RefreshBluetoothCache) {
    # 删除旧的缓存文件
    if (Test-Path $CacheFilePath) {
        Remove-Item $CacheFilePath -ErrorAction SilentlyContinue
    }
    $bluetoothDevices = Get-PnpDevice -Class "Bluetooth" | Select-Object DeviceID, Name
    foreach ($bluetoothDevice in $bluetoothDevices) {
        $powerStatus = Get-PnpDeviceProperty -InstanceId $bluetoothDevice.DeviceID -KeyName $BatteryKey
        $isConnected = Get-PnpDeviceProperty -InstanceId $bluetoothDevice.DeviceID -KeyName $IsConnectedKey
        if ($powerStatus.Data -and $isConnected.Data) {
            Write-Host "---"
            Write-Host "设备：$($bluetoothDevice.Name)" -ForegroundColor Blue
            Write-Host "电量：$($powerStatus.Data)%"
            Write-Host "已刷新该设备缓存" -ForegroundColor Green
            Write-BluetoothCache -Device $bluetoothDevice
        }
    }
    exit 0
}

# 主逻辑
$capacityInfo = Get-BatteryCapacityInfo

if (-not $capacityInfo) {
    exit 1
}

# 输出基础信息
if ($capacityInfo.DesignCapacity) {
    Write-Host "设计最大容量: $([math]::Round($capacityInfo.DesignCapacity / 1000, 2)) Wh"
}
if ($capacityInfo.FullChargeCapacity) {
    Write-Host "当前实际容量: $([math]::Round($capacityInfo.FullChargeCapacity / 1000, 2)) Wh"
}
if ($capacityInfo.DesignCapacity -and $capacityInfo.FullChargeCapacity) {
    $healthPercentage = [math]::Round(($capacityInfo.FullChargeCapacity / $capacityInfo.DesignCapacity) * 100, 2)
    Write-Host "电池的健康度: $healthPercentage%"
}
Write-Host "电脑当前电量: $(Get-CurrentBatteryCharge)%"

# 如果是监控模式
if ($Monitor) {
    Write-Host "---"
    Write-Host "您正在持续监测功率，使用 Ctrl + C 退出。`n请注意：`n功率监测严格根据电量变化计算，在脚本启动时或状态变化（如由放电转为充电）时的一次功率计算通常是不准确的。`n此脚本的电量直接从 Win32_Battery 获取，可能与托盘中显示的电量有微小差异，请以脚本为准。`n充电功率是净功率，充电器的输出功率约为显示的充电功率加上先前的放电功率。" -ForegroundColor Yellow
    Write-Host "---"
    
    # 初始化监控状态
    $monitorState = Initialize-MonitorState -FullChargeCapacity $capacityInfo.FullChargeCapacity
    
    # 监控循环
    while ($true) {
        Start-Sleep 10
        
        $currentCharge = Get-CurrentBatteryCharge
        
        # 仅在电量发生变化时才执行后续逻辑
        if (Test-ChargeChange -CurrentCharge $currentCharge -LastChargePercent $monitorState.LastChargePercent) {
            # 计算功率
            $powerWatts = Get-BatteryPower -CurrentCharge $currentCharge -MonitorState $monitorState
            
            # 输出结果
            Write-ColoredOutput -CurrentCharge $currentCharge -PowerWatts $powerWatts -FullChargeCapacity $capacityInfo.FullChargeCapacity
            
            # 更新状态
            $monitorState.LastChargePercent = $currentCharge
            $monitorState.LastTimestamp = Get-Date
        }
    }
}
