<#
.SYNOPSIS
    清理 PowerShell 命令历史中的指定记录

.DESCRIPTION
    这个脚本可以根据不同的匹配模式查找并删除 PowerShell 命令历史中的指定记录。
    支持预览匹配项、选择性保留和自动备份功能。

.PARAMETER Like
    使用通配符模式匹配命令（如 "git *"）

.PARAMETER Force
    跳过确认提示，直接删除所有匹配项

.EXAMPLE
    .\Clear-SpecifiedHistory.ps1 -Like "git reset *"
    删除所有以 "git reset" 开头的命令

.EXAMPLE
    .\Clear-SpecifiedHistory.ps1 -Like "npm install *" -Force
    删除所有以 "npm install" 开头的命令，跳过确认
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Like,
    
    [switch]$Force  # 跳过确认直接删除
)

# 参数验证函数
function Test-FilterPattern {
    param([string]$pattern)
    
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        Write-Host "错误：匹配模式不能为空。" -ForegroundColor Red
        return $false
    }
    return $true
}

# 过滤命令函数
function Get-FilteredCommands {
    param($commands, $filterPattern)
    
    return $commands | Where-Object { $_ -like $filterPattern }
}

# 显示匹配命令预览函数
function Show-MatchedCommands {
    param($matchedCommands)
    
    if ($matchedCommands.Count -eq 0) {
        Write-Host "没有找到匹配的历史记录。" -ForegroundColor Yellow
        return $false
    }
    
    # 计算数字宽度
    $numberWidth = $matchedCommands.Count.ToString().Length
    
    Write-Host "`n找到 $($matchedCommands.Count) 条匹配的历史记录：" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $matchedCommands.Count; $i++) {
        $number = $i + 1
        # 奇数行用默认色，偶数行用紫色
        if ($number % 2 -eq 0) {
            Write-Host ("{0,$numberWidth}    {1}" -f $number, $matchedCommands[$i]) -ForegroundColor Magenta
        }
        else {
            Write-Host ("{0,$numberWidth}    {1}" -f $number, $matchedCommands[$i])
        }
    }
    
    return $true
}

# 用户交互函数
function Get-UserConfirmation {
    param($matchedCount)
    
    Write-Host "`n请选择操作：" -ForegroundColor Yellow
    Write-Host "  a    - 全部删除 ($matchedCount 条记录)"
    Write-Host "  sn   - 保留第 n 条记录，逗号分隔（如 s1,3,5 保留第1、3、5条）"
    Write-Host "  q    - 取消操作"
    
    do {
        $choice = Read-Host "`n请输入选择"
        $choice = $choice.Trim().ToLower()
        
        if ($choice -eq "a") {
            return @{ Action = "DeleteAll" }
        }
        elseif ($choice -eq "q") {
            return @{ Action = "Cancel" }
        }
        elseif ($choice -match "^s[\d,\s]+$") {
            # 解析保留的索引
            $keepIndices = @()
            $numbers = $choice.Substring(1) -split "[,\s]+" | Where-Object { $_ -match "^\d+$" }
            foreach ($num in $numbers) {
                $index = [int]$num
                if ($index -ge 1 -and $index -le $matchedCount) {
                    $keepIndices += $index - 1  # 转换为0基索引
                }
            }
            return @{ Action = "Selective"; KeepIndices = $keepIndices }
        }
        else {
            Write-Host "无效输入，请重新选择。" -ForegroundColor Red
        }
    } while ($true)
}

# 选择性删除函数
function Remove-SelectiveCommands {
    param($allCommands, $matchedCommands, $keepIndices)
    
    # 创建要保留的匹配命令列表
    $commandsToKeep = @()
    for ($i = 0; $i -lt $matchedCommands.Count; $i++) {
        if ($i -in $keepIndices) {
            $commandsToKeep += $matchedCommands[$i]
        }
    }
    
    # 从所有命令中移除不保留的匹配命令
    $resultCommands = @()
    foreach ($command in $allCommands) {
        if ($command -in $matchedCommands -and $command -notin $commandsToKeep) {
            # 这是要删除的匹配命令，跳过
            continue
        }
        $resultCommands += $command
    }
    
    return $resultCommands
}

# 保存过滤后的历史记录函数
function Save-FilteredHistory {
    param($commands, $historyPath)
    
    try {
        $commands | Set-Content -Path $historyPath -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "错误：无法保存历史文件：$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 删除结果统计函数
function Show-DeletionSummary {
    param($originalCount, $finalCount, $matchedCount, $keptCount = 0)
    
    $actualDeleted = $originalCount - $finalCount
    
    Write-Host "`n删除操作完成：" -ForegroundColor Green
    Write-Host "  原始记录数: $originalCount"
    Write-Host "  匹配记录数: $matchedCount"
    if ($keptCount -gt 0) {
        Write-Host "  保留记录数: $keptCount"
    }
    Write-Host "  实际删除数: $actualDeleted"
    Write-Host "  剩余记录数: $finalCount"
}

# 主程序函数
function Main {
    # 参数验证
    if (-not (Test-FilterPattern -pattern $Like)) {
        exit 1
    }
    
    # 获取历史文件路径
    $historySavePath = (Get-PSReadlineOption).HistorySavePath
    if (-not (Test-Path -Path $historySavePath -PathType Leaf)) {
        Write-Host "错误：命令历史文件不存在于路径: $historySavePath" -ForegroundColor Red
        exit 1
    }
    
    # 读取历史记录
    try {
        $existingCommands = @(Get-Content -Path $historySavePath -Encoding UTF8 -ErrorAction Stop)
    }
    catch {
        Write-Host "错误：无法读取历史文件：$($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
    # 查找匹配的命令
    $matchedCommands = @(Get-FilteredCommands -commands $existingCommands -filterPattern $Like)
    
    # 显示预览
    if (-not (Show-MatchedCommands -matchedCommands $matchedCommands)) {
        exit 0
    }
    
    # 用户确认（除非使用 -Force）
    if (-not $Force) {
        $userChoice = Get-UserConfirmation -matchedCount $matchedCommands.Count
        
        if ($userChoice.Action -eq "Cancel") {
            Write-Host "操作已取消。" -ForegroundColor Yellow
            exit 0
        }
    }
    else {
        $userChoice = @{ Action = "DeleteAll" }
    }
    
    # 执行删除操作
    switch ($userChoice.Action) {
        "DeleteAll" {
            $newCommands = $existingCommands | Where-Object { $_ -notin $matchedCommands }
            $keptCount = 0
        }
        "Selective" {
            $newCommands = Remove-SelectiveCommands -allCommands $existingCommands -matchedCommands $matchedCommands -keepIndices $userChoice.KeepIndices
            $keptCount = $userChoice.KeepIndices.Count
        }
    }
    
    # 保存结果
    if (Save-FilteredHistory -commands $newCommands -historyPath $historySavePath) {
        Show-DeletionSummary -originalCount $existingCommands.Count -finalCount $newCommands.Count -matchedCount $matchedCommands.Count -keptCount $keptCount
    }
    else {
        exit 1
    }
}

# 执行主程序
Main
