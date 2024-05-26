# コンセプト
- Minioをファイルサーバとして使う。docker-composeで環境を構築
- アップロード権限とダウンロード権限を分ける
- 多数のWindowsクライアントでPowerShellスクリプトを使い、HTTPリクエストでデスクトップ上のファイルを送信
- 運用担当者はSMBファイル共有を使い、Minioからデータを一括ダウンロード

## Linuxサーバ
```bash
podman-compose up -d

# install minio client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# setup users
mc alias set myminio http://localhost:8000 admin j0SgwZVhmuVe

mc admin user add myminio soc-cattle peJzwaFi2jUe
mc admin policy attach myminio readonly --user soc-cattle
mc admin user svcacct add myminio soc-cattle

mc admin user add myminio soc-operator cVJS8jfKyQjv
mc admin policy attach myminio readwrite --user soc-operator
mc admin user svcacct add myminio soc-operator

# setup bucket
mc mb myminio/collector
mc anonymous set upload myminio/collector
mc quota set myminio/collector --size 2GiB
mc ilm rule add --expire-days 14 myminio/collector

mc mb myminio/redistribute
mc anonymous set download myminio/redistribute
mc quota set myminio/redistribute --size 30GiB
mc ilm rule add --expire-days 14 myminio/redistribute

mc anonymous get myminio/collector
mc anonymous get myminio/redistribute


```

## クライアント
```powershell
.\upload-local-file.ps1 -fileName "example.txt"
```

## 運用担当者
```powershell
.\download-all-files.ps1 -fileName "example.txt" -downloadPath "C:\path\to\save\example.txt"
```