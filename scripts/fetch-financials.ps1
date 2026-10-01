param([switch]$UseCached)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$dataDir = Join-Path $projectRoot 'data'
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
$rawPath = Join-Path $dataDir 'dart-financials-2025-raw.json'
$xmlPath = Join-Path $dataDir 'dart-report-2025.xml'

if (!$UseCached) {
    $keyLine = Get-Content (Join-Path $projectRoot '.env') -Encoding UTF8 |
        Where-Object { $_ -match '^\s*DART_API_KEY\s*=' } | Select-Object -First 1
    if (!$keyLine) { throw 'DART_API_KEY is missing from .env.' }
    $apiKey = ($keyLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
    if (!$apiKey) { throw 'DART_API_KEY is empty.' }
    $apiRoot = 'https://opendart.fss.or.kr/api/'
    try {
        $response = Invoke-RestMethod -Uri ($apiRoot + 'fnlttSinglAcntAll.json?crtfc_key=' +
            [uri]::EscapeDataString($apiKey) + '&corp_code=01390344&bsns_year=2025&reprt_code=11011&fs_div=CFS') -TimeoutSec 60
    } catch { throw 'OpenDART financial request failed. Request URL and key are suppressed.' }
    if ($response.status -ne '000') { throw ('OpenDART status: ' + $response.status) }
    [IO.File]::WriteAllText($rawPath, ($response | ConvertTo-Json -Depth 20), $utf8)
    $receipt = $response.list[0].rcept_no
    $zipPath = Join-Path $dataDir 'dart-report-2025.zip'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri ($apiRoot + 'document.xml?crtfc_key=' +
            [uri]::EscapeDataString($apiKey) + '&rcept_no=' + $receipt) -OutFile $zipPath -TimeoutSec 60
    } catch { throw 'OpenDART document request failed. Request URL and key are suppressed.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = $zip.GetEntry($receipt + '.xml')
        if (!$entry) { throw 'Main report XML was not found in the archive.' }
        $reader = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
        try { [IO.File]::WriteAllText($xmlPath, $reader.ReadToEnd(), $utf8) }
        finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
}

$response = Get-Content $rawPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($response.status -ne '000') { throw 'Cached financial response is not successful.' }
$receipt = $response.list[0].rcept_no
$xml = Get-Content $xmlPath -Raw -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $dataDir 'dart-report-2025.zip'))
try {
    $sourceEntry = $archive.GetEntry($receipt + '.xml')
    if (!$sourceEntry) { throw 'Report archive and financial receipt do not match.' }
    $sourceReader = New-Object IO.StreamReader($sourceEntry.Open(), [Text.Encoding]::UTF8)
    try {
        if ($sourceReader.ReadToEnd() -cne $xml) { throw 'Report XML differs from the archived original.' }
    } finally { $sourceReader.Dispose() }
} finally { $archive.Dispose() }
$reportUrl = 'https://dart.fss.or.kr/dsaf001/main.do?rcpNo=' + $receipt
$metrics = @()
foreach ($definition in @(
    @{ id='revenue'; label='매출액'; account='ifrs-full_Revenue' },
    @{ id='operating_profit'; label='영업이익'; account='dart_OperatingIncomeLoss' }
)) {
    $rows = @($response.list | Where-Object {
        $_.account_id -eq $definition.account -and $_.sj_div -in @('IS','CIS')
    })
    if ($rows.Count -ne 1) { throw ('Expected exactly one account: ' + $definition.account) }
    $row = $rows[0]
    if ($row.currency -ne 'KRW' -or $row.bsns_year -ne '2025' -or $row.corp_code -ne '01390344') {
        throw 'Unexpected currency, year or company.'
    }
    $amount = [long]($row.thstrm_amount -replace ',', '')
    $metrics += [ordered]@{
        id=$definition.id; label=$definition.label; value=$amount; unit='KRW'
        value_100_million_krw=([decimal]$amount / 100000000)
        period_start='2025-01-01'; period_end='2025-12-31'; basis='연결재무제표'
        source=[ordered]@{ endpoint='fnlttSinglAcntAll.json'; account_id=$row.account_id
            account_name=$row.account_nm; statement=$row.sj_nm; raw_value=$row.thstrm_amount
            receipt_no=$receipt; url=$reportUrl }
    }
}

# Parse only the order-status section and fail if its structure or units change.
$section = [regex]::Match($xml, '(?s)<P[^>]*>다\. 수주상황</P>(.*?)</SECTION-2>').Value
if (!$section.Contains('2025년 12월 31일') -or !$section.Contains('(단위 : 백만원)')) {
    throw 'Order backlog date/unit could not be verified.'
}
$tables = @([regex]::Matches($section, '(?s)<TABLE\b.*?</TABLE>') |
    Where-Object { $_.Value.Contains('기말수주잔고') -and $_.Value.Contains('<THEAD>') })
if ($tables.Count -ne 1) { throw 'Expected exactly one order backlog table.' }
[xml]$table = $tables[0].Value
$breakdown = @()
$total = $null
foreach ($tr in $table.TABLE.TBODY.TR) {
    $cells = @($tr.TD)
    $label = $cells[0].InnerText -replace '\s', ''
    $amount = [long]($cells[-1].InnerText -replace ',', '')
    if ($label -eq '합계') { $total = $amount }
    else { $breakdown += [ordered]@{ label=$label; value_million_krw=$amount; value_krw=($amount * 1000000L) } }
}
$sum = ($breakdown | ForEach-Object { $_.value_million_krw } | Measure-Object -Sum).Sum
if ($null -eq $total -or $sum -ne $total) { throw 'Order backlog components do not reconcile.' }
$metrics += [ordered]@{
    id='order_backlog'; label='수주잔고'; value=($total * 1000000L); unit='KRW'
    value_100_million_krw=([decimal]$total / 100); as_of='2025-12-31'
    basis='사업보고서 II. 사업의 내용 / 4. 매출 및 수주상황 / 다. 수주상황, 기말수주잔고 합계'
    breakdown=$breakdown
    source=[ordered]@{ endpoint='document.xml'; raw_value=$total; raw_unit='백만원'
        receipt_no=$receipt; url=$reportUrl }
}
$result = [ordered]@{
    company='HD현대중공업'; corp_code='01390344'; business_year=2025
    report_code='11011'; report_name='사업보고서 (2025.12)'; receipt_no=$receipt
    source_url=$reportUrl; generated_at=[DateTimeOffset]::Now.ToString('o')
    source_downloaded_at=(Get-Item $rawPath).LastWriteTimeUtc.ToString('o')
    metrics=$metrics
    notes=@('매출액 및 영업이익은 2025 회계연도 연결재무제표 당기금액입니다.',
        '수주잔고는 재무제표 계정이 아닌 사업보고서 수주상황의 2025-12-31 기말 합계입니다.',
        '수주현황에는 사업결합 및 외화계약 환율변동, 계약 취소와 금액 변경 등이 반영되어 있습니다.',
        '원 단위 환산값을 저장하되 수주잔고의 원문 공시 정밀도는 백만원입니다.')
}
[IO.File]::WriteAllText((Join-Path $dataDir 'financials.json'), ($result | ConvertTo-Json -Depth 20), $utf8)
$lines = @('# HD현대중공업 2025년 사업보고서', '', '| 항목 | 금액(억원) | 기준 |', '|---|---:|---|')
foreach ($metric in $metrics) {
    $period = if ($metric.id -eq 'order_backlog') { '2025-12-31 기말' } else { '2025년 연결' }
    $lines += '| ' + $metric.label + ' | ' + $metric.value_100_million_krw.ToString('N5', [cultureinfo]'en-US') + ' | ' + $period + ' |'
}
$lines += @('', ('[사업보고서 원문](' + $reportUrl + ')'), '', '수주잔고는 사업보고서 수주상황에서 추출했으며 원문 단위는 백만원입니다.', '',
    '재조회: `powershell -ExecutionPolicy Bypass -File scripts/fetch-financials.ps1`',
    '저장된 원본으로 재생성: `powershell -ExecutionPolicy Bypass -File scripts/fetch-financials.ps1 -UseCached`')
[IO.File]::WriteAllText((Join-Path $dataDir 'financials.md'), ($lines -join "`n"), $utf8)
$metrics | ForEach-Object { [pscustomobject]@{ metric=$_.label; KRW=$_.value; hundred_million_KRW=$_.value_100_million_krw } } | Format-Table
