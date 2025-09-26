<#
.SYNOPSIS
创建文件的硬链接，支持批量操作和自定义路径，并可记录和检查链接状态

.DESCRIPTION
该脚本可以为指定文件创建硬链接，支持批量选择和路径自定义，
同时记录已创建的链接（格式：硬链接绝对路径 -> 源相对路径）并提供检查功能，
确保已处理的源路径及其子路径被正确排除

硬链接只能用于文件，不支持目录。默认为递归文件模式。

不推荐在硬链接路径下启动该脚本，务必保持启动脚本位置为数据源目录

硬链接通常不需要管理员权限，只需要对目标目录有写权限即可
#>

param(
    [switch]$Check,
    [switch]$NoRecurse
)

# 加载功能模块
$scriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$functionScriptPath = Join-Path -Path $scriptDirectory -ChildPath "HardLinkFunctions.ps1"

if (-not (Test-Path -Path $functionScriptPath)) {
    Write-Host "未找到功能模块文件: $functionScriptPath" -ForegroundColor Red
    exit 1
}
. $functionScriptPath

# 硬链接记录文件路径
$logFilePath = Join-Path -Path $PWD.Path -ChildPath "hardlinks_windows.log"

# 自定义路径选项
$customLocations = @(
    "C:\",
    "~\Soft\"
)

# 已记录的源目录和链接
$recordedSourceDirs = @()
$recordedLinks = @()

# 加载已记录的链接
Read-RecordedLinks -logFilePath $logFilePath -recordedLinks ([ref]$recordedLinks) -recordedSourceDirs ([ref]$recordedSourceDirs)

# 检查模式
if ($Check) {
    Confirm-HardLinks -logFilePath $logFilePath -recordedLinks $recordedLinks
    exit 0
}

# 硬链接只支持文件模式
$itemType = "文件"

# 显示当前模式
$modeInfo = if ($NoRecurse) { "文件模式（非递归）" } else { "文件模式（递归）" }
Write-Host "当前模式: $modeInfo" -ForegroundColor Yellow

# 主循环
while ($true) {
    # 获取符合条件的项目（硬链接只处理文件）
    $items = Get-ItemsToProcess -isFileMode $true -NoRecurse $NoRecurse -recordedSourceDirs $recordedSourceDirs
    
    if (-not $items -or $items.Count -eq 0) {
        # 使用花括号包裹变量确保正确解析
        Write-Host "`n当前目录下没有未处理的${itemType}（已排除所有记录的源路径及其子路径）。" -ForegroundColor Yellow
        $choice = Read-Host "是否继续等待？(y/n)"
        if ($choice -eq 'n') { exit }
        else { continue }
    }
    
    # 计算数字宽度
    $numberWidth = $items.Count.ToString().Length
    
    # 列出项目，花括号包裹变量（添加隔行颜色显示）
    Write-Host "`n当前目录下的未处理${itemType}列表：" -ForegroundColor Cyan
    for ($i = 0; $i -lt $items.Count; $i++) {
        $number = $i + 1
        $relativePath = Convert-ToRelativePath -absolutePath $items[$i].FullName -baseDirectory $PWD.Path
        # 奇数行用默认色，偶数行用紫色
        if ($number % 2 -eq 0) {
            Write-Host ("{0,$numberWidth}    {1}" -f $number, $relativePath) -ForegroundColor Magenta
        }
        else {
            Write-Host ("{0,$numberWidth}    {1}" -f $number, $relativePath)
        }
    }
    
    # 显示已处理数量，花括号包裹变量
    if ($recordedSourceDirs.Count -gt 0) {
        Write-Host "`n已处理 $($recordedSourceDirs.Count) 个${itemType}及其子路径（已跳过）"
    }
    
    # 询问用户选择，花括号包裹变量
    $userInput = Read-Host "`n请输入要创建硬链接的${itemType}编号（空格分隔多个，输入 q 退出）"
    
    # 处理退出命令
    if ($userInput -eq 'q' -or $userInput -eq 'Q') {
        Write-Host "`n脚本已退出。" -ForegroundColor Green
        exit
    }
    
    # 解析输入编号
    $selectedNumbers = $userInput -split '\s+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    
    # 验证编号
    $validSelections = @()
    foreach ($num in $selectedNumbers) {
        if ($num -ge 1 -and $num -le $items.Count) {
            $validSelections += $num - 1
        }
        else {
            # 花括号包裹变量
            Write-Host "警告：无效的${itemType}编号 $num，已忽略。" -ForegroundColor Yellow
        }
    }
    
    # 检查有效选择，花括号包裹变量
    if ($validSelections.Count -eq 0) {
        Write-Host "没有有效的${itemType}选择。" -ForegroundColor Red
        continue
    }
    
    # 路径选择菜单
    Write-Host "`n请选择硬链接创建位置：" -ForegroundColor Cyan
    Write-Host "  enter - 默认位置（将相对路径的第一个 . 替换为 ~）"
    Write-Host "  s - 显示自定义路径选单"
    Write-Host "  i - 输入自定义路径"
    Write-Host "  q - 退出脚本"
    
    $locationChoice = Read-Host "请输入选择"
    
    # 处理位置选择
    if ($locationChoice -eq 'q' -or $locationChoice -eq 'Q') {
        Write-Host "`n脚本已退出。" -ForegroundColor Green
        exit
    }
    
    # 确定基础路径
    $basePath = $null
    switch ($locationChoice) {
        's' {
            $pathNumberWidth = $customLocations.Count.ToString().Length
            Write-Host "`n自定义路径选单：" -ForegroundColor Cyan
            for ($i = 0; $i -lt $customLocations.Count; $i++) {
                $number = $i + 1
                Write-Host ("{0,$pathNumberWidth}    {1}" -f $number, $customLocations[$i])
            }
            
            $pathNum = Read-Host "请选择路径编号"
            if ($pathNum -match '^\d+$' -and [int]$pathNum -ge 1 -and [int]$pathNum -le $customLocations.Count) {
                $basePath = $customLocations[[int]$pathNum - 1]
            }
            else {
                Write-Host "无效选择，使用默认路径。" -ForegroundColor Yellow
                $basePath = "~\"
            }
        }
        'i' {
            $basePath = Read-Host "请输入基础路径"
            if ([string]::IsNullOrWhiteSpace($basePath)) {
                Write-Host "路径不能为空，使用默认路径。" -ForegroundColor Yellow
                $basePath = "~\"
            }
            if (-not $basePath.EndsWith('\')) { $basePath += '\' }
        }
        default {
            $basePath = "~\"
        }
    }
    
    # 创建硬链接
    foreach ($index in $validSelections) {
        $sourceItem = $items[$index]
        $result = New-HardLink -sourcePath $sourceItem.FullName -basePath $basePath `
            -currentDirectory $PWD.Path -logFilePath $logFilePath `
            -recordedSourceDirs ([ref]$recordedSourceDirs) -recordedLinks ([ref]$recordedLinks)
        if ($result) {
            Write-Host "[成功] 硬链接已创建或已存在（路径：$($sourceItem.FullName)）" -ForegroundColor Green
        }
        else {
            Write-Host "[失败] 硬链接创建未完成（路径：$($sourceItem.FullName)）" -ForegroundColor Red
        }
        
        Write-Host "`n当前批次操作完成。" -ForegroundColor Cyan
        Write-Host "按任意键继续..."
        $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
        Clear-Host

        # 显示当前模式
        Write-Host "当前模式: $modeInfo" -ForegroundColor Yellow
    }
}
