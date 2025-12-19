# 定义参数块，允许脚本直接接收 -Path 参数
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path
)

# 确保加载必要的程序集
Add-Type -AssemblyName Microsoft.VisualBasic

function Remove-ToRecycleBinInternal {
    param($Target)
    
    # 解析路径，处理相对路径或通配符（Listary 通常传绝对路径，该处理稍微增加了一些通用性）
    $item = Get-Item -LiteralPath $Target -ErrorAction SilentlyContinue

    if ($null -eq $item) {
        Write-Error "删除失败: 未找到文件或目录 $Target"
        Start-Sleep 2
        return
    }

    $fullpath = $item.FullName

    try {
        if ($item.PSIsContainer) {
            # 删除目录
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($fullpath, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        else {
            # 删除文件
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($fullpath, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        Write-Host "成功将 $fullpath 移至回收站" -ForegroundColor Green
        Start-Sleep 2
    }
    catch {
        Write-Error "删除失败：$_"
        Start-Sleep 2
    }
}

# 执行逻辑
Remove-ToRecycleBinInternal -Target $Path
