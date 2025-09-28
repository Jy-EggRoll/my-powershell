[CmdletBinding()]
param(
    [switch]$Monitor,
    [switch]$wait,
    [switch]$Bluetooth,
    [switch]$BluetoothMonitor,
    [switch]$RefreshBluetoothCache
)

# 蓝牙相关常量和配置
$BatteryKey = "{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"
$CacheFilePath = "BluetoothDeviceIDCache.txt"

# 缓存管理函数
function Test-BluetoothCacheExists {
    return Test-Path $CacheFilePath
}

function Read-BluetoothCache {
    if (Test-BluetoothCacheExists) {
        try {
            $cacheContent = Get-Content $CacheFilePath
            $devices = @()
            foreach ($line in $cacheContent) {
                if ($line -and $line.Contains("|")) {
                    $parts = $line -split "\|", 2
                    if ($parts.Length -eq 2) {
                        $devices += @{
                            DeviceID = $parts[0]
                            Name     = $parts[1]
                        }
                    }
                }
            }
            return $devices
        }
        catch {
            Write-Warning "缓存文件损坏，将删除并重新生成"
            Remove-BluetoothCache
            return $null
        }
    }
    return $null
}

function Write-BluetoothCache {
    param($Devices)
    
    try {
        $cacheContent = @()
        foreach ($device in $Devices) {
            $cacheContent += "$($device.DeviceID)|$($device.Name)"
        }
        $cacheContent | Set-Content $CacheFilePath -Encoding UTF8
        return $true
    }
    catch {
        Write-Warning "无法写入缓存文件: $_"
        return $false
    }
}

function Remove-BluetoothCache {
    if (Test-BluetoothCacheExists) {
        try {
            Remove-Item $CacheFilePath -Force
            return $true
        }
        catch {
            Write-Warning "无法删除缓存文件: $_"
            return $false
        }
    }
    return $true
}

# 蓝牙设备查询函数
function Test-BluetoothDeviceConnected {
    param($DeviceID)
    
    try {
        $device = Get-PnpDevice -InstanceId $DeviceID -ErrorAction SilentlyContinue
        return $device -and $device.Status -eq "OK"
    }
    catch {
        return $false
    }
}

function Get-AllBluetoothDevicesWithBattery {
    $bluetoothDevices = Get-PnpDevice -Class "Bluetooth" | Select-Object DeviceID, Name
    $devicesWithBattery = @()
    
    foreach ($bluetoothDevice in $bluetoothDevices) {
        # 检查设备是否连接
        if (-not (Test-BluetoothDeviceConnected -DeviceID $bluetoothDevice.DeviceID)) {
            continue
        }
        
        try {
            $powerStatus = Get-PnpDeviceProperty -InstanceId $bluetoothDevice.DeviceID -KeyName $BatteryKey -ErrorAction SilentlyContinue
            if ($powerStatus -and $powerStatus.Data) {
                $devicesWithBattery += @{
                    DeviceID     = $bluetoothDevice.DeviceID
                    Name         = $bluetoothDevice.Name
                    BatteryLevel = $powerStatus.Data
                }
            }
        }
        catch {
            # 忽略无法获取电量的设备
        }
    }
    
    return $devicesWithBattery
}

function Get-CachedBluetoothDevicesBattery {
    param($CachedDevices)
    
    $devicesWithBattery = @()
    $validDevices = @()
    
    foreach ($cachedDevice in $CachedDevices) {
        # 检查设备是否仍然存在且连接
        if (-not (Test-BluetoothDeviceConnected -DeviceID $cachedDevice.DeviceID)) {
            continue
        }
        
        try {
            $powerStatus = Get-PnpDeviceProperty -InstanceId $cachedDevice.DeviceID -KeyName $BatteryKey -ErrorAction SilentlyContinue
            if ($powerStatus -and $powerStatus.Data) {
                $devicesWithBattery += @{
                    DeviceID     = $cachedDevice.DeviceID
                    Name         = $cachedDevice.Name
                    BatteryLevel = $powerStatus.Data
                }
                $validDevices += $cachedDevice
            }
        }
        catch {
            # 设备不存在或无法访问，从缓存中移除
        }
    }
    
    # 如果有设备被移除，更新缓存
    if ($validDevices.Count -ne $CachedDevices.Count) {
        Write-BluetoothCache -Devices $validDevices
    }
    
    return $devicesWithBattery
}

# 用户交互函数
function Request-UserConsent {
    Write-Host "检测到您首次使用蓝牙电量查询功能。" -ForegroundColor Yellow
    Write-Host "为了提高查询速度，脚本可以缓存有电量信息的蓝牙设备ID。" -ForegroundColor Yellow
    Write-Host "这将显著减少后续查询的时间，避免每次都扫描所有蓝牙设备。" -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "是否创建缓存文件？(Y/N)"
    return $response -match "^[Yy]"
}

function Show-BluetoothCacheNotice {
    Write-Host "提示：正在使用蓝牙设备缓存加速查询。" -ForegroundColor Green
    Write-Host "当蓝牙设备状态有更新时，请使用 -RefreshBluetoothCache 参数刷新缓存。" -ForegroundColor Green
    Write-Host ""
}

# 蓝牙电量显示函数
function Show-BluetoothBatteryInfo {
    param($Devices)
    
    if ($Devices.Count -eq 0) {
        Write-Host "未找到有电量信息的蓝牙设备。" -ForegroundColor Yellow
        return
    }
    
    Write-Host "蓝牙设备电量信息：" -ForegroundColor Cyan
    Write-Host "---" -ForegroundColor Cyan
    
    foreach ($device in $Devices) {
        Write-Host "设备：$($device.Name)" -ForegroundColor White
        Write-Host "电量：$($device.BatteryLevel)%" -ForegroundColor Green
        Write-Host ""
    }
}

function Get-BluetoothDeviceBattery {
    param(
        [bool]$UseCache = $true,
        [bool]$ForceRefresh = $false
    )
    
    # 如果强制刷新，删除现有缓存
    if ($ForceRefresh) {
        Remove-BluetoothCache
        Write-Host "已清除缓存，重新扫描蓝牙设备..." -ForegroundColor Yellow
    }
    
    $devicesWithBattery = @()
    
    if ($UseCache -and -not $ForceRefresh) {
        # 尝试使用缓存
        $cachedDevices = Read-BluetoothCache
        if ($cachedDevices) {
            Show-BluetoothCacheNotice
            $devicesWithBattery = Get-CachedBluetoothDevicesBattery -CachedDevices $cachedDevices
        }
        else {
            # 询问用户是否创建缓存
            $createCache = Request-UserConsent
            if ($createCache) {
                Write-Host "正在扫描蓝牙设备并创建缓存，请稍等..." -ForegroundColor Yellow
                $devicesWithBattery = Get-AllBluetoothDevicesWithBattery
                # 保存到缓存
                $cacheDevices = @()
                foreach ($device in $devicesWithBattery) {
                    $cacheDevices += @{
                        DeviceID = $device.DeviceID
                        Name     = $device.Name
                    }
                }
                Write-BluetoothCache -Devices $cacheDevices
                Write-Host "缓存已创建，下次查询将更快。" -ForegroundColor Green
            }
            else {
                Write-Host "正在扫描蓝牙设备，请稍等..." -ForegroundColor Yellow
                $devicesWithBattery = Get-AllBluetoothDevicesWithBattery
            }
        }
    }
    else {
        # 直接全扫描
        Write-Host "正在扫描蓝牙设备，请稍等..." -ForegroundColor Yellow
        $devicesWithBattery = Get-AllBluetoothDevicesWithBattery
    }
    
    Show-BluetoothBatteryInfo -Devices $devicesWithBattery
    return $devicesWithBattery
}

# 蓝牙监测功能
function Initialize-BluetoothMonitorState {
    param($Devices)
    
    $monitorState = @{
        Devices       = @{}
        LastTimestamp = Get-Date
        IsInitialized = $true
    }
    
    foreach ($device in $Devices) {
        $monitorState.Devices[$device.DeviceID] = @{
            Name             = $device.Name
            LastBatteryLevel = $device.BatteryLevel
            LastTimestamp    = Get-Date
            TrendData        = @()
        }
    }
    
    return $monitorState
}

function Update-BluetoothMonitorState {
    param($MonitorState, $CurrentDevices)
    
    $currentTime = Get-Date
    $hasChanges = $false
    
    foreach ($device in $CurrentDevices) {
        if ($MonitorState.Devices.ContainsKey($device.DeviceID)) {
            $deviceState = $MonitorState.Devices[$device.DeviceID]
            
            # 检查电量是否变化
            if ($device.BatteryLevel -ne $deviceState.LastBatteryLevel) {
                $deviceState.LastBatteryLevel = $device.BatteryLevel
                $deviceState.LastTimestamp = $currentTime
                $hasChanges = $true
                
                # 记录趋势数据（保留最近10个数据点）
                $deviceState.TrendData += @{
                    BatteryLevel = $device.BatteryLevel
                    Timestamp    = $currentTime
                }
                if ($deviceState.TrendData.Count -gt 10) {
                    $deviceState.TrendData = $deviceState.TrendData[-10..-1]
                }
            }
        }
        else {
            # 新设备
            $MonitorState.Devices[$device.DeviceID] = @{
                Name             = $device.Name
                LastBatteryLevel = $device.BatteryLevel
                LastTimestamp    = $currentTime
                TrendData        = @(@{
                        BatteryLevel = $device.BatteryLevel
                        Timestamp    = $currentTime
                    })
            }
            $hasChanges = $true
        }
    }
    
    return $hasChanges
}

function Calculate-BluetoothBatteryTrend {
    param($DeviceState)
    
    if ($DeviceState.TrendData.Count -lt 2) {
        return $null
    }
    
    $trendData = $DeviceState.TrendData
    $firstPoint = $trendData[0]
    $lastPoint = $trendData[-1]
    
    $timeDiff = ($lastPoint.Timestamp - $firstPoint.Timestamp).TotalMinutes
    if ($timeDiff -le 0) {
        return $null
    }
    
    $batteryDiff = $lastPoint.BatteryLevel - $firstPoint.BatteryLevel
    $batteryChangePerMinute = $batteryDiff / $timeDiff
    
    return $batteryChangePerMinute
}

function Get-BluetoothBatteryTimeEstimate {
    param($CurrentLevel, $BatteryChangePerMinute)
    
    if ([math]::Abs($BatteryChangePerMinute) -lt 0.001) {
        return $null
    }
    
    if ($BatteryChangePerMinute -gt 0) {
        # 充电中 - 计算充满时间
        $minutesToFull = (100 - $CurrentLevel) / $BatteryChangePerMinute
    }
    else {
        # 放电中 - 计算耗尽时间
        $minutesToEmpty = $CurrentLevel / [math]::Abs($BatteryChangePerMinute)
        $minutesToFull = $minutesToEmpty
    }
    
    # 计算未来时间
    $futureTime = (Get-Date).AddMinutes($minutesToFull)
    return "{0:D2} 月 {1:D2} 日 {2:D2}:{3:D2}" -f $futureTime.Month, $futureTime.Day, $futureTime.Hour, $futureTime.Minute
}

function Write-BluetoothMonitorOutput {
    param($MonitorState)
    
    Write-Host "蓝牙设备电量监测：" -ForegroundColor Cyan
    Write-Host "---" -ForegroundColor Cyan
    
    foreach ($deviceId in $MonitorState.Devices.Keys) {
        $deviceState = $MonitorState.Devices[$deviceId]
        $trend = Calculate-BluetoothBatteryTrend -DeviceState $deviceState
        
        Write-Host "设备：$($deviceState.Name)" -ForegroundColor White
        Write-Host "电量：$($deviceState.LastBatteryLevel)%" -ForegroundColor Green
        
        if ($trend) {
            $trendSign = if ($trend -gt 0) { "+" } else { "" }
            $trendFormatted = "{0}{1:F3}" -f $trendSign, $trend
            
            if ($trend -gt 0) {
                $status = "充电中"
                $color = "Green"
            }
            else {
                $status = "放电中"
                $color = "Red"
            }
            
            Write-Host "状态：$status，变化率：$trendFormatted %/分钟" -ForegroundColor $color
            
            # 时间预测
            $timeEstimate = Get-BluetoothBatteryTimeEstimate -CurrentLevel $deviceState.LastBatteryLevel -BatteryChangePerMinute $trend
            if ($timeEstimate) {
                if ($trend -gt 0) {
                    Write-Host "预计充满：$timeEstimate" -ForegroundColor Green
                }
                else {
                    Write-Host "预计耗尽：$timeEstimate" -ForegroundColor Red
                }
            }
        }
        
        Write-Host ""
    }
}

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

# 参数互斥性检查
$bluetoothParams = @($Bluetooth, $BluetoothMonitor, $RefreshBluetoothCache)
$bluetoothParamCount = ($bluetoothParams | Where-Object { $_ }).Count
$batteryParams = @($Monitor, $wait)
$batteryParamCount = ($batteryParams | Where-Object { $_ }).Count

if ($bluetoothParamCount -gt 1) {
    Write-Error "蓝牙相关参数不能同时使用：-Bluetooth, -BluetoothMonitor, -RefreshBluetoothCache"
    exit 1
}

if ($bluetoothParamCount -gt 0 -and $batteryParamCount -gt 0) {
    Write-Error "蓝牙参数和电池参数不能同时使用"
    exit 1
}

# 处理蓝牙相关参数
if ($RefreshBluetoothCache) {
    # 强制刷新缓存并运行蓝牙查询
    Get-BluetoothDeviceBattery -UseCache $true -ForceRefresh $true
    exit 0
}
elseif ($Bluetooth) {
    # 运行蓝牙查询
    Get-BluetoothDeviceBattery -UseCache $true
    exit 0
}
elseif ($BluetoothMonitor) {
    # 运行蓝牙监测模式
    Write-Host "您正在持续监测蓝牙设备电量，使用 Ctrl + C 退出。" -ForegroundColor Yellow
    Write-Host "请注意：电量变化率基于设备电量变化计算，初始计算可能不准确。" -ForegroundColor Yellow
    Write-Host "---"
    
    # 获取初始蓝牙设备
    $initialDevices = Get-BluetoothDeviceBattery -UseCache $true
    if ($initialDevices.Count -eq 0) {
        Write-Host "未找到有电量信息的蓝牙设备，退出监测。" -ForegroundColor Red
        exit 1
    }
    
    # 初始化监测状态
    $bluetoothMonitorState = Initialize-BluetoothMonitorState -Devices $initialDevices
    
    # 监测循环
    while ($true) {
        Start-Sleep 30  # 蓝牙设备监测间隔较长
        
        # 获取当前设备状态
        $currentDevices = Get-BluetoothDeviceBattery -UseCache $true
        
        # 更新监测状态并检查变化
        $hasChanges = Update-BluetoothMonitorState -MonitorState $bluetoothMonitorState -CurrentDevices $currentDevices
        
        if ($hasChanges) {
            Clear-Host
            Write-BluetoothMonitorOutput -MonitorState $bluetoothMonitorState
        }
    }
}

# 如果没有蓝牙相关参数，执行原有电池功能
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