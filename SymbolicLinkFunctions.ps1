<#
.SYNOPSIS
符号链接管理工具的功能模块，包含所有辅助函数
#>

<#
.SYNOPSIS
标准化路径，移除末尾的反斜杠并确保为绝对路径（修复根路径问题）
#>
function Resolve-Path {
    param(
        [string]$path
    )
    
    # 解析为绝对路径
    $absolutePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
    
    # 移除路径末尾的反斜杠，但保留根路径的反斜杠（如 C:\）
    if ($absolutePath -match '^[A-Za-z]:\\$') {
        # 根路径，保持原样
        return $absolutePath
    }
    else {
        # 非根路径，移除末尾反斜杠
        return $absolutePath -replace '\\+$', ''
    }
}

<#
.SYNOPSIS
将绝对路径转换为相对于基准目录的相对路径
#>
function Convert-ToRelativePath {
    param(
        [string]$absolutePath,
        [string]$baseDirectory
    )
    
    $absolutePath = Resolve-Path $absolutePath
    $baseDirectory = Resolve-Path $baseDirectory
    
    # 创建路径对象
    $absolutePathObj = [System.IO.Path]::GetFullPath($absolutePath)
    $baseDirObj = [System.IO.Path]::GetFullPath($baseDirectory)
    
    # 生成相对路径
    $relativePath = [System.IO.Path]::GetRelativePath($baseDirObj, $absolutePathObj)
    
    # 处理当前目录情况
    if ($relativePath -eq [System.IO.Path]::GetFileName($absolutePathObj)) {
        return ".\$relativePath"
    }
    
    return $relativePath
}

<#
.SYNOPSIS
将相对路径转换为绝对路径（基于基准目录）
#>
function Convert-ToAbsolutePath {
    param(
        [string]$relativePath,
        [string]$baseDirectory
    )
    
    $baseDirectory = Resolve-Path $baseDirectory
    return Resolve-Path (Join-Path -Path $baseDirectory -ChildPath $relativePath)
}

<#
.SYNOPSIS
检查路径是否为指定目录或其子目录
#>
function Test-IsSubPath {
    param(
        [string]$path,
        [string]$parentPath
    )
    
    $normalizedPath = Resolve-Path $path
    $normalizedParent = Resolve-Path $parentPath
    
    # 检查是否为同一目录或子目录
    return $normalizedPath -eq $normalizedParent -or $normalizedPath -like "$normalizedParent\*"
}

<#
.SYNOPSIS
加载已记录的符号链接信息并确保源路径（含子路径）被正确排除
#>
function Read-RecordedLinks {
    param(
        [string]$logFilePath,
        [ref]$recordedLinks,
        [ref]$recordedSourceDirs
    )
    
    if (Test-Path -Path $logFilePath) {
        try {
            $content = Get-Content -Path $logFilePath -Raw -ErrorAction Stop
            $lines = $content -split "`n" | Where-Object { $_ -match '->' -and $_.Trim() -ne '' }
            
            # 使用 ArrayList 提高性能
            $tempLinks = [System.Collections.ArrayList]::new()
            $tempSourceDirs = [System.Collections.ArrayList]::new()
            
            foreach ($line in $lines) {
                $parts = $line -split '->' | ForEach-Object { $_.Trim() }
                if ($parts.Count -eq 2) {
                    try {
                        $linkPath = Resolve-Path $parts[0]
                        $sourceRelativePath = $parts[1]
                        $sourcePath = Convert-ToAbsolutePath -relativePath $sourceRelativePath -baseDirectory $PWD.Path
                        
                        # 添加到临时集合
                        $null = $tempLinks.Add([PSCustomObject]@{
                            LinkPath           = $linkPath
                            SourcePath         = $sourcePath
                            SourceRelativePath = $sourceRelativePath
                        })
                        
                        if ($sourcePath -notin $tempSourceDirs) {
                            $null = $tempSourceDirs.Add($sourcePath)
                        }
                    }
                    catch {
                        Write-Warning "无法解析日志行: $line - $_"
                    }
                }
            }
            
            # 转换为数组并赋值给引用参数
            $recordedLinks.Value = $tempLinks.ToArray()
            $recordedSourceDirs.Value = $tempSourceDirs.ToArray()
            
            Write-Host "已加载 $($recordedLinks.Value.Count) 条符号链接记录，排除 $($recordedSourceDirs.Value.Count) 个源路径及其子路径"
        }
        catch {
            Write-Error "读取符号链接记录文件失败: $_"
            $recordedLinks.Value = @()
            $recordedSourceDirs.Value = @()
        }
    }
}

<#
.SYNOPSIS
保存符号链接信息到日志文件（格式：符号链接绝对路径 -> 源相对路径）
#>
function Save-SymlinkRecord {
    param(
        [string]$logFilePath,
        [string]$linkPath,
        [string]$sourcePath
    )
    
    try {
        # 标准化路径
        $normalizedLinkPath = Resolve-Path $linkPath
        $normalizedSourcePath = Resolve-Path $sourcePath
        
        # 计算源路径相对于当前目录的相对路径
        $sourceRelativePath = Convert-ToRelativePath -absolutePath $normalizedSourcePath -baseDirectory $PWD.Path
        
        $line = "$normalizedLinkPath -> $sourceRelativePath"
        Add-Content -Path $logFilePath -Value $line -Encoding UTF8 -ErrorAction Stop
        Write-Host "已记录符号链接信息到日志"
    }
    catch {
        Write-Error "保存符号链接记录失败: $_"
    }
}

<#
.SYNOPSIS
检查已记录的符号链接是否有效，并提供逐个处理无效链接的选项
#>
function Confirm-Symlinks {
    param(
        [string]$logFilePath,
        [array]$recordedLinks
    )
    
    if (-not (Test-Path -Path $logFilePath)) {
        Write-Host "未找到符号链接记录文件: $logFilePath" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n开始检查符号链接有效性...`n" -ForegroundColor Cyan
    
    # 修复：使用数组切片复制而非 ToArray() 方法
    $validLinks = @($recordedLinks)  # 初始化为所有记录，后续仅移除需要删除的
    $processedCount = 0
    $invalidCount = 0

    foreach ($link in $recordedLinks) {
        $processedCount++
        $status = "有效"
        $reason = ""
        
        # 检查符号链接是否存在
        if (-not (Test-Path -Path $link.LinkPath)) {
            $status = "无效"
            $reason = "符号链接不存在"
        }
        # 检查符号链接是否指向正确的目标
        else {
            $item = Get-Item -Path $link.LinkPath -Force -ErrorAction SilentlyContinue
            if (-not $item -or -not ($item.Attributes -match 'ReparsePoint')) {
                $status = "无效"
                $reason = "不是有效的符号链接"
            }
            else {
                try {
                    # 标准化路径后再比较（安全处理目标不存在的情况）
                    $targetPath = $item.Target
                    if (Test-Path -Path $targetPath) {
                        $normalizedTarget = Resolve-Path $targetPath
                        $normalizedSource = Resolve-Path $link.SourcePath
                        
                        if ($normalizedTarget -ne $normalizedSource) {
                            $status = "不一致"
                            $reason = "目标已更改: $($item.Target)"
                        }
                    }
                    else {
                        $status = "无效"
                        $reason = "符号链接指向不存在的目标: $targetPath"
                    }
                }
                catch {
                    $status = "无效"
                    $reason = "无法解析符号链接目标: $_"
                }
                
                # 检查源路径是否存在
                if ($status -eq "有效" -and -not (Test-Path -Path $link.SourcePath)) {
                    $status = "无效"
                    $reason = "源路径不存在"
                }
            }
        }
        
        # 处理有效链接
        if ($status -eq "有效") {
            Write-Host "[$processedCount/$($recordedLinks.Count)] $($link.LinkPath) -> $($link.SourceRelativePath) - 有效" -ForegroundColor Green
            continue
        }
        
        # 处理无效链接
        $invalidCount++
        Write-Host "[$processedCount/$($recordedLinks.Count)] 发现问题链接:" -ForegroundColor Red
        Write-Host "链接路径: $($link.LinkPath)"
        Write-Host "预期源: $($link.SourceRelativePath)"
        Write-Host "状态: $status ($reason)" -ForegroundColor Red
        
        # 询问用户处理方式
        do {
            $choice = Read-Host "请选择操作 (r=重建, i=忽略, d=删除) [r/i/d]"
            $choice = $choice.ToLower()
        } while ($choice -notin @('r', 'i', 'd'))
        
        switch ($choice) {
            'r' {
                # 尝试重建符号链接（使用标准流程但不添加新记录）
                Write-Host "尝试重建符号链接..." -ForegroundColor Cyan
                
                # 1. 检查目标路径是否存在并处理
                if (Test-Path -Path $link.LinkPath) {
                    Write-Host "移除现有无效链接..." -ForegroundColor Yellow
                    Remove-Item -Path $link.LinkPath -Force -ErrorAction SilentlyContinue -Recurse
                }

                # 2. 确保父目录存在
                $parentDir = Split-Path -Path $link.LinkPath -Parent
                if (-not (Test-Path -Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                    Write-Host "已创建父目录: $parentDir"
                }

                # 3. 执行重建（标准创建流程）
                try {
                    New-Item -ItemType SymbolicLink -Path $link.LinkPath -Target $link.SourcePath | Out-Null
                    Write-Host "符号链接重建成功" -ForegroundColor Green
                    # 重建成功保持原记录（不添加新记录）
                }
                catch {
                    Write-Host "符号链接重建失败: $_" -ForegroundColor Red
                }
            }
            'i' {
                Write-Host "已忽略此链接，保留记录" -ForegroundColor Yellow
                # 保留在validLinks中
            }
            'd' {
                # 删除符号链接（如果存在）和记录
                if (Test-Path -Path $link.LinkPath) {
                    try {
                        Remove-Item -Path $link.LinkPath -Force -ErrorAction Stop
                        Write-Host "已删除符号链接" -ForegroundColor Yellow
                    }
                    catch {
                        Write-Host "删除符号链接失败: $_" -ForegroundColor Red
                    }
                }
                Write-Host "已从记录中移除" -ForegroundColor Yellow
                # 从有效链接中移除
                $validLinks = $validLinks | Where-Object { $_.LinkPath -ne $link.LinkPath }
            }
        }
    }
    
    Write-Host "`n检查完成。共检查 $processedCount 个链接，发现 $invalidCount 个无效链接。" -ForegroundColor Cyan
    
    # 更新日志文件（仅当有删除操作时）
    if ($validLinks.Count -ne $recordedLinks.Count) {
        try {
            if ($validLinks.Count -gt 0) {
                $content = $validLinks | ForEach-Object { "$($_.LinkPath) -> $($_.SourceRelativePath)" }
                Set-Content -Path $logFilePath -Value $content -Encoding UTF8 -ErrorAction Stop
                Write-Host "已更新符号链接记录，保留 $($validLinks.Count) 条记录。" -ForegroundColor Green
            }
            else {
                Remove-Item -Path $logFilePath -Force -ErrorAction Stop
                Write-Host "已删除所有符号链接记录。" -ForegroundColor Green
            }
        }
        catch {
            Write-Error "更新记录文件失败: $_"
        }
    }
    else {
        Write-Host "所有符号链接记录保持不变。" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
获取符合条件的项目（文件或文件夹）列表
#>
function Get-ItemsToProcess {
    param(
        [bool]$isFileMode,
        [bool]$noRecurse,
        [array]$recordedSourceDirs
    )
    
    try {
        # 根据模式确定获取文件还是文件夹，使用 PowerShell 7 支持的参数
        $items = if ($isFileMode) {
            # 获取文件
            if ($noRecurse) {
                Get-ChildItem -File -ErrorAction Stop
            }
            else {
                Get-ChildItem -File -Recurse -ErrorAction Stop
            }
        }
        else {
            # 获取目录
            if ($noRecurse) {
                Get-ChildItem -Directory -ErrorAction Stop
            }
            else {
                Get-ChildItem -Directory -Recurse -ErrorAction Stop
            }
        }
        
        # 如果没有已记录的目录，直接返回所有项目
        if ($recordedSourceDirs.Count -eq 0) {
            return $items
        }
        
        # 预处理已记录目录路径，避免在循环中重复调用 Resolve-Path
        $normalizedRecordedDirs = $recordedSourceDirs | ForEach-Object { Resolve-Path $_ }
        
        # 排除已记录的源目录及其子目录（优化版本）
        return $items | Where-Object {
            $itemPath = Resolve-Path $_.FullName
            # 使用简化的字符串比较而不是函数调用
            $isExcluded = $false
            foreach ($recordedDir in $normalizedRecordedDirs) {
                if ($itemPath -eq $recordedDir -or $itemPath -like "$recordedDir\*") {
                    $isExcluded = $true
                    break
                }
            }
            -not $isExcluded
        }
    }
    catch {
        Write-Error "获取项目列表失败: $_"
        return @()
    }
}

<#
.SYNOPSIS
创建符号链接
#>
function New-Symlink {
    param(
        [string]$sourcePath,
        [string]$basePath,
        [string]$currentDirectory,
        [string]$logFilePath,
        [ref]$recordedSourceDirs,
        [ref]$recordedLinks
    )
    
    $normalizedSourcePath = Resolve-Path $sourcePath
    # 显示源的相对路径
    $sourceRelativePath = Convert-ToRelativePath -absolutePath $normalizedSourcePath -baseDirectory $currentDirectory
    Write-Host "`n处理: $sourceRelativePath" -ForegroundColor DarkCyan
    
    # 获取相对路径（用于构建目标路径）
    $relativePath = Convert-ToRelativePath -absolutePath $sourcePath -baseDirectory $currentDirectory
    
    # 构建目标路径（替换相对路径的第一个 .\）
    if ($relativePath -like ".\*") {
        $targetPath = $relativePath -replace '^\.', $basePath
    }
    else {
        $targetPath = Join-Path -Path $basePath -ChildPath $relativePath
    }
    
    # 解析路径中的 ~ 符号（安全处理）
    if ($targetPath -like "*~*") {
        $targetPath = $targetPath -replace '~', [Environment]::GetFolderPath('UserProfile')
    }
    $targetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($targetPath)
    $normalizedTargetPath = Resolve-Path $targetPath
    
    Write-Host "目标符号链接路径: $normalizedTargetPath"
    
    # 检查目标路径是否存在
    if (Test-Path -Path $targetPath) {
        Write-Host "目标路径已存在。" -ForegroundColor Yellow
        
        # 检查是否是符号链接
        $item = Get-Item -Path $targetPath -Force
        if ($item.Attributes -match 'ReparsePoint') {
            # 是符号链接
            try {
                $linkTarget = $item.Target
                if (Test-Path -Path $linkTarget) {
                    $normalizedLinkTarget = Resolve-Path $linkTarget
                    if ($normalizedLinkTarget -eq $normalizedSourcePath) {
                        Write-Host "符号链接已存在且指向正确位置，无需操作。" -ForegroundColor Green
                        # 记录此链接（如果尚未记录）
                        if (-not ($recordedLinks.Value | Where-Object { $_.LinkPath -eq $normalizedTargetPath -and $_.SourcePath -eq $normalizedSourcePath })) {
                            Save-SymlinkRecord -logFilePath $logFilePath -linkPath $normalizedTargetPath -sourcePath $normalizedSourcePath
                        }
                        return $true
                    }
                    else {
                        # 增强提示：明确显示当前链接指向的位置
                        Write-Host "`n警告：符号链接已存在但指向不同位置！" -ForegroundColor Red
                        Write-Host "当前符号链接指向: $($item.Target)" -ForegroundColor Red
                        Write-Host "您尝试链接到: $sourceRelativePath" -ForegroundColor Yellow
                        
                        # 询问用户是否替换
                        $confirm = Read-Host "`n是否删除现有符号链接并创建新的？(y/n)"
                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                            Write-Host "删除现有符号链接..." -ForegroundColor Yellow
                            Remove-Item -Path $targetPath -Force -Recurse
                        }
                        else {
                            Write-Host "已跳过。" -ForegroundColor Cyan
                            return $false
                        }
                    }
                }
                else {
                    Write-Host "符号链接指向不存在的目标，将替换。" -ForegroundColor Yellow
                    Remove-Item -Path $targetPath -Force -Recurse
                }
            }
            catch {
                Write-Host "符号链接指向无效目标，将替换。" -ForegroundColor Yellow
                Remove-Item -Path $targetPath -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
        else {
            # 不是符号链接
            if ($item.PSIsContainer) {
                # 是目录，检查是否为空
                $childItems = Get-ChildItem -Path $targetPath -Force
                if ($childItems.Count -eq 0) {
                    Write-Host "目标是为空目录，将删除并替换为符号链接。" -ForegroundColor Yellow
                    Remove-Item -Path $targetPath -Recurse -Force
                }
                else {
                    # 目录不为空，询问用户
                    $confirm = Read-Host "目标目录不为空，是否强制删除并替换为符号链接？(y/n)"
                    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                        Write-Host "删除目录并创建符号链接..." -ForegroundColor Yellow
                        Remove-Item -Path $targetPath -Recurse -Force
                    }
                    else {
                        Write-Host "已跳过。" -ForegroundColor Cyan
                        return $false
                    }
                }
            }
            else {
                # 是文件
                $confirm = Read-Host "目标是一个文件，是否删除并替换为符号链接？(y/n)"
                if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                    Write-Host "删除文件并创建符号链接..." -ForegroundColor Yellow
                    Remove-Item -Path $targetPath -Force -Recurse
                }
                else {
                    Write-Host "已跳过。" -ForegroundColor Cyan
                    return $false
                }
            }
        }
    }
    
    # 创建符号链接
    try {
        # 确保目标路径的父目录存在
        $parentDir = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path -Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            Write-Host "已创建父目录: $parentDir"
        }
        
        # 创建符号链接
        New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath | Out-Null
        Write-Host "符号链接创建成功！" -ForegroundColor Green
        
        # 记录符号链接信息（自动转换为相对路径）
        Save-SymlinkRecord -logFilePath $logFilePath -linkPath $normalizedTargetPath -sourcePath $normalizedSourcePath
        
        # 添加到内存中的记录，避免重新显示（包括子路径）
        if ($normalizedSourcePath -notin $recordedSourceDirs.Value) {
            $recordedSourceDirs.Value += $normalizedSourcePath
        }
        $recordedLinks.Value += [PSCustomObject]@{
            LinkPath           = $normalizedTargetPath
            SourcePath         = $normalizedSourcePath
            SourceRelativePath = $sourceRelativePath
        }
        return $true
    }
    catch {
        Write-Host "创建符号链接失败: $_" -ForegroundColor Red
        return $false
    }
}
