param (
    [string]$filePath,
    [string]$minioEndpoint = "http://your-minio-server:8000"
)

[string]$bucketName = "collector"
[string]$accessKey = "soc-cattle"
[string]$secretKey = "peJzwaFi2jUe"

# Minio用の認証ヘッダーを作成
$authHeader = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${accessKey}:${secretKey}"))
}

# ファイルをアップロード
$fileName = [System.IO.Path]::GetFileName($filePath)
$url = "$minioEndpoint/$bucketName/$fileName"
Invoke-RestMethod -Uri $url -Method Put -InFile $filePath -Headers $authHeader

Write-Host "File uploaded successfully to $url"
