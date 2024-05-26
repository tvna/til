param (
    [string]$downloadPath,
    [string]$minioEndpoint = "http://your-minio-server:8000"
)

[string]$bucketName = "collector"
[string]$accessKey = "soc-operator"
[string]$secretKey = "cVJS8jfKyQjv"

# 必要なモジュールをインポート
Import-Module -Name WebRequest

# Minio用の認証ヘッダーを作成
$authHeader = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$accessKey:$secretKey"))
}

# ファイルリストを取得
$listUrl = "$minioEndpoint/$bucketName?list-type=2"
$response = Invoke-RestMethod -Uri $listUrl -Method Get -Headers $authHeader

# 取得したファイルリストからKey（ファイル名）を抽出
$fileList = $response.ListBucketResult.Contents | ForEach-Object { $_.Key }

# ダウンロードディレクトリを作成（存在しない場合）
if (!(Test-Path -Path $downloadPath)) {
    New-Item -ItemType Directory -Path $downloadPath
}

# 各ファイルをダウンロード
foreach ($file in $fileList) {
    $fileUrl = "$minioEndpoint/$bucketName/$file"
    $outputFile = Join-Path -Path $downloadPath -ChildPath $file
    Invoke-RestMethod -Uri $fileUrl -Method Get -Headers $authHeader -OutFile $outputFile
    Write-Host "Downloaded $file to $outputFile"
}

Write-Host "All files have been downloaded successfully to $downloadPath"
