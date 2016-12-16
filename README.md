# jenkins_scripts
Jenkins Scripts (Shell or Git or ...)  
本項目裏的腳本是配合 Jenkins 使用的一些有助於提高工作效率的工具。

# 説明
## git_merge.sh
用於特定分支的合併操作。  

如目前團隊要求的規範：  
提交測試後，源碼從 develop 分支合併到 release 分支，在 release 分支上構建測試環境；  
測試通過後，源碼從 release 分支合併到 master 分支，在 master 分支上構建（預）生產環境；  
如線上出現嚴重 bug 需要緊急修復，從 master 分支拉起特定版本到 hotfix 分支進行 bug 修復；  
緊急 bug 修復後源碼從 hotfix 分支合併回 master 分支。  

此腳本可選擇需要操作的版本庫（項目需要，存在多個版本庫）、合併的分支、  
可填寫需要修復 bug 的版本，更詳細的可查看腳本裏面的説明。

## git_tag.sh
用於迭代版本上線後的打標籤操作。  

可輸入標籤名稱和標籤説明，之後判斷標籤名稱是否規範、是否已經存在，  
最後則獲取 master 分支最新提交，在最新提交上添加該標籤。  

## auto_build_when_git_push.md
教程：Git 倉庫有更新時自動觸發 Jenkins 構建項目
