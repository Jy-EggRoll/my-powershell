param(
    [Parameter(Mandatory = $false)]
    [string]$StartDir = (Get-Location).Path
)

# 检查起始目录是否有效
if (-not (Test-Path -Path $StartDir -PathType Container)) {
    Write-Error "错误：目录 '$StartDir' 不存在或不是有效的目录"
    exit 1
}

function Update-GitRepositories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootDir
    )

    try {
        # 找出所有名为 .git 的目录
        $gitDirs = Get-ChildItem -Path $RootDir -Directory -Filter ".git" -Depth 1 -Force  # 仅查找当前目录下的 .git 目录，扫描深度仅为 1，扫描隐藏目录
    }
    catch {
        Write-Warning "无法列出目录：$RootDir - 错误：$($_.Exception.Message)"
        return
    }

    # 取出父目录（仓库目录）并去重
    $repos = $gitDirs | ForEach-Object { $_.Parent.FullName }

    if (-not $repos -or $repos.Count -eq 0) {
        Write-Host "未在 $RootDir 下发现任何包含 .git 目录的仓库" -ForegroundColor Yellow
        return
    }

    foreach ($repo in $repos) {
        Write-Host "正在处理 Git 仓库：$repo" -ForegroundColor Magenta

        # 使用 git -C 来避免更改当前工作目录
        git -C "$repo" fetch --recurse-submodules
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$repo 执行 fetch 成功" -ForegroundColor Green
        }
        else {
            Write-Host "$repo 执行 fetch 失败（退出码：$LASTEXITCODE）" -ForegroundColor Red
        }
    }
}

# 开始递归处理
Write-Host "当前目录：$StartDir" -ForegroundColor Green
Update-GitRepositories -RootDir $StartDir

Write-Host "所有目录处理完毕" -ForegroundColor Green
