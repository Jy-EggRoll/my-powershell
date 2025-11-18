<#
.SYNOPSIS
递归查询目录下的所有 Git 仓库并执行 git fetch 操作

.DESCRIPTION
从指定目录（默认当前目录）开始，递归遍历所有子目录，识别 Git 仓库（含 .git 子目录），并依次执行 git fetch。
自动跳过符号链接目录以避免循环引用。

.PARAMETER StartDir
起始目录路径，默认当前目录

.EXAMPLE
.\Git-FetchAll.ps1
处理当前目录下的所有 Git 仓库

.EXAMPLE
.\Git-FetchAll.ps1 "D:\Projects"
处理 D:\Projects 目录下的所有 Git 仓库
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$StartDir = (Get-Location).Path
)

# 检查起始目录是否有效
if (-not (Test-Path -Path $StartDir -PathType Container)) {
    Write-Error "错误：目录 '$StartDir' 不存在或不是有效的目录"
    exit 1
}

# 递归处理目录的函数
function Process-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentDir
    )

    # 获取当前目录下的所有子目录（包含隐藏目录，排除符号链接）
    $subDirs = Get-ChildItem -Path $CurrentDir -Directory | Where-Object {
        # 排除符号链接目录（避免循环引用）
        $_.LinkType -ne 'SymbolicLink'
    }

    foreach ($dir in $subDirs) {
        $dirPath = $dir.FullName
        # 检查是否为 Git 仓库（存在 .git 子目录）
        $gitDir = Join-Path -Path $dirPath -ChildPath ".git"
        if (Test-Path -Path $gitDir -PathType Container) {
            Write-Host "正在处理 Git 仓库：$dirPath" -ForegroundColor Cyan

            # 进入仓库目录执行 git fetch（使用 Push-Location 确保操作后返回原目录）
            Push-Location -Path $dirPath -ErrorAction SilentlyContinue
            if ($LASTEXITCODE -ne 0) {
                Write-Error "无法进入目录：$dirPath"
                continue
            }

            # 执行 git fetch 并捕获结果
            git fetch --recurse-submodules  # 可以递归 fetch 子模块
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$dirPath 执行 fetch 成功" -ForegroundColor Green
            }
            else {
                Write-Host "$dirPath 执行 fetch 失败" -ForegroundColor Red
            }

            # 回到原目录
            Pop-Location
        }
        else {
            # 不是 Git 仓库，递归处理子目录
            Process-Directory -CurrentDir $dirPath
        }
    }
}

# 开始递归处理
Write-Host "开始处理父目录：$StartDir" -ForegroundColor Green
Process-Directory -CurrentDir $StartDir

Write-Host "所有目录处理完毕" -ForegroundColor Green
