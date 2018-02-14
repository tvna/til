# setup
Composeファイル以外で定義する設定を記載

## Grafana
1. Grafanaにアクセスし、ログイン (http://localhost/)
  - user : grafana
  - password : grafana
2. Sidebar -> Datasource -> Add data source
3. 下記を入力してADD
  - name : Prometheus
  - type : Prometheus
  - url : http://prometheus:9090
  - access : proxy
4. Sidebar -> Dashboard -> Import Dashboard
5. Import 395 (https://grafana.com/dashboards/395)
