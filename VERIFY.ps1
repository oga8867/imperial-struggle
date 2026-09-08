param(
    [string]$GodotExe = $env:GODOT_EXE
)

# 사용자 저장을 건드리지 않는 검증 실행기다. 게임 규칙, 카드, 경계 조건,
# 여러 판의 진행, 실제 UI 연결을 서로 다른 검사로 나누어 실패 원인을 찾는다.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = 'X:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot executable not found. Pass -GodotExe or set GODOT_EXE.'
}
$projectPath = Join-Path $PSScriptRoot 'godot_project'
$reportPath = Join-Path $PSScriptRoot 'output\validation'
$profilePath = Join-Path $PSScriptRoot 'tmp\validation\verification-profile'
New-Item -ItemType Directory -Path $reportPath, $profilePath -Force | Out-Null
$oldAppData = $env:APPDATA
$testCases = @(
    @{ Name = 'rules_regression'; Pattern = 'RULES REGRESSION: 53 passed, 0 failed' },
    @{ Name = 'card_regression'; Pattern = 'CARD REGRESSION: 97 passed, 0 failed' },
    @{ Name = 'edge_regression'; Pattern = 'EDGE REGRESSION: 42 passed, 0 failed' },
    @{ Name = 'ministry_regression'; Pattern = 'MINISTRY REGRESSION: 39 passed, 0 failed' },
    @{ Name = 'diplomacy_regression'; Pattern = 'DIPLOMACY REGRESSION: 33 passed, 0 failed' },
    @{ Name = 'locale_regression'; Pattern = 'LOCALE REGRESSION: 20 passed, 0 failed' },
    @{ Name = 'campaign_regression'; Pattern = 'CAMPAIGN REGRESSION: 12 completed' },
    @{ Name = 'ui_smoke'; Pattern = '=== UI SMOKE PASS ===' },
    @{ Name = 'ui_smoke_en'; Scene = 'ui_smoke'; English = $true; Pattern = '=== UI SMOKE PASS ===' }
)
$results = @()
try {
    $env:APPDATA = $profilePath
    foreach ($case in $testCases) {
        $env:APPDATA = Join-Path $profilePath $case.Name
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
        $logPath = Join-Path $reportPath ($case.Name + '.log')
        $scene = if ($case.Scene) { $case.Scene } else { $case.Name }
        $arguments = @('--headless', '--path', ('"' + $projectPath + '"'),
            '--log-file', ('"' + $logPath + '"'), '--quit-after', '10000',
            ('res://scenes/' + $scene + '.tscn'))
        if ($case.English) { $arguments += @('--', '--english') }
        $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $timedOut = -not $process.WaitForExit(90000)
        if ($timedOut) {
            # 이 실행기가 방금 시작한 검사 프로세스만 종료한다.
            $process.Kill()
            $process.WaitForExit()
        }
        $process.Refresh()
        $content = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { '' }
        # 종료 코드만으로는 파싱 오류를 놓칠 수 있다. 완료 문구와 오류도 함께 확인한다.
        # 이 PC의 인증서 저장소 경고는 네트워크를 사용하지 않는 검사와 무관하다.
        $errors = @($content -split "`r?`n" | Where-Object {
            $_ -match 'SCRIPT ERROR:|Parse Error:|^FAIL|^ERROR:' -and
            $_ -notmatch '^ERROR: Failed to read the root certificate store\.'
        })
        $ok = -not $timedOut -and $process.ExitCode -eq 0 -and
            $content.Contains($case.Pattern) -and $errors.Count -eq 0
        if ($case.English) { $ok = $ok -and $content.Contains('UI LOCALE en') }
        $result = [ordered]@{
            test = $case.Name; passed = $ok; exit_code = $process.ExitCode
            timed_out = $timedOut; errors = $errors; log = $logPath
        }
        $results += $result
        Write-Host (('{0}: {1}' -f $case.Name, $(if ($ok) { 'PASS' } else { 'FAIL' })))
    }
} finally {
    $env:APPDATA = $oldAppData
}
$report = [ordered]@{
    checked_at = (Get-Date).ToString('o')
    engine = $GodotExe
    passed = @($results | Where-Object { -not $_.passed }).Count -eq 0
    results = $results
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportPath 'summary.json') -Encoding utf8
if (-not $report.passed) { exit 1 }
Write-Host 'ALL VALIDATION PASSED'
