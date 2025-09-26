[CmdletBinding()]
param(
    [switch]$Monitor,
    [switch]$wait
)

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