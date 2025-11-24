param(
    [Parameter(Mandatory = $false)]
    [string]$StartDir = (Get-Location).Path,
    [switch]$Fetch,
    [switch]$Pull,
    [switch]$Status,
    [switch]$ToShallow,
    [switch]$GC
)

# 检查起始目录是否有效
if (-not (Test-Path -Path $StartDir -PathType Container)) {
    Write-Error "错误：目录 '$StartDir' 不存在或不是有效的目录"
    exit 1
}

function Update-GitRepositories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootDir,
        [Parameter(Mandatory = $false)]
        [ValidateSet('fetch', 'pull', 'status', 'toshallow', 'gc')]
        [string]$Action
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

        switch ($Action) {
            'fetch' {
                git -C "$repo" fetch --recurse-submodules
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "$repo 执行 fetch 成功" -ForegroundColor Green
                }
                else {
                    Write-Host "$repo 执行 fetch 失败（退出码：$LASTEXITCODE）" -ForegroundColor Red
                }
            }
            'pull' {
                git -C "$repo" pull --recurse-submodules
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "$repo 执行 pull 成功" -ForegroundColor Green
                }
                else {
                    Write-Host "$repo 执行 pull 失败（退出码：$LASTEXITCODE）" -ForegroundColor Red
                }
            }
            'status' {
                Write-Host "$repo 状态：" -ForegroundColor Cyan
                git -C "$repo" status --untracked-files
                Write-Host "$repo 状态获取完成" -ForegroundColor Green
            }
            'toshallow' {
                # 转为浅克隆（尽量只保留最近的 3 个提交），并包含子模块
                git -C "$repo" fetch --depth 3 --recurse-submodules
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "$repo 执行 fetch --depth 3 成功" -ForegroundColor Green
                }
                else {
                    Write-Host "$repo 执行 fetch --depth 3 失败（退出码：$LASTEXITCODE）" -ForegroundColor Red
                }
            }
            'gc' {
                git -C "$repo" gc
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "$repo 执行 gc 成功" -ForegroundColor Green
                }
                else {
                    Write-Host "$repo 执行 gc 失败（退出码：$LASTEXITCODE）" -ForegroundColor Red
                }
            }
        }
    }
}


# 校验互斥参数：只允许一个动作开关
$actionCount = @($Fetch, $Pull, $Status, $ToShallow, $GC) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($actionCount -gt 1) {
    Write-Error "错误：只可指定其中之一：-Fetch、-Pull、-Status、-ToShallow 或 -GC"
    Show-Help
    exit 1
}

# 如果没有指定任何动作，则默认使用 status
if ($actionCount -eq 0) {
    $Action = 'status'
}
else {
    # 由开关设置动作类型
    if ($Fetch) { $Action = 'fetch' }
    elseif ($Pull) { $Action = 'pull' }
    elseif ($Status) { $Action = 'status' }
    elseif ($ToShallow) { $Action = 'toshallow' }
    elseif ($GC) { $Action = 'gc' }
}

# 开始递归处理
Write-Host "当前目录：$StartDir，动作：$Action" -ForegroundColor Green
Update-GitRepositories -RootDir $StartDir -Action $Action

Write-Host "所有目录处理完毕" -ForegroundColor Green
