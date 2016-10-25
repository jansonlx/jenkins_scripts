# Git 倉庫更新時自動構建 Jenkins 項目

## 説明

　　項目中使用了 Gogs 搭建 Git 服務存放項目源碼，使用 Jenkins 實現項目的部署。  
　　由於生產環境的配置文件中存在數據庫配置等敏感信息，需要存放在獨立的 Git 倉庫中，  
需要實現的效果是：當存放配置文件的 Git 倉庫一有更新，Jenkins 上對應項目則觸發構建。

## 步驟
1. Jenkins 安裝插件

  在 Jenkins 上安裝 [Gogs Webhook Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Gogs+Webhook+Plugin) 插件。

2. Jenkins 創建項目

  在 Jenkins 上新建一個構建程序的項目，获取该 Jenkins 项目名稱，如「Config-Auto-Update」

3. 在 Git 上添加 webhook

  進入對應的 Git 倉庫的設置頁面，在「Webhooks」設置項中添加新的 webhook，其中：  
 Payload URL：格式「http(s)://<< jenkins-server >>/gogs-webhook/?job=<< jobname >>」，如「http://192.168.1.2:8080/gogs-webhook/?job=Config-Auto-Update」；
 Secret：可自定義填寫，後面需要使用。

4. Jenkins 項目上輸入 Secret

  修改步驟 2 的 Jenkins 項目，在「General」標籤下勾選「Use Gogs secret」，之後輸入步驟 3 的自定義 Secret 即可。