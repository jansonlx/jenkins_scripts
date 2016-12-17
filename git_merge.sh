#!/bin/bash -e

###############################################################################
# 腳本：Merge Branch via Jenkins
# 功能：合併指定分支到特定分支
# 作者：
#        ____ __   __  __ _____ ___  __  __
#       /_  /  _ \/ / / / ____/ __ \/ / / /
#        / / /_/ / /|/ /_/_  / / / / /|/ /
#     __/ / /-/ / / | /___/ / /_/ / / | /
#    /___/_/ /_/_/|_|/_____/\____/_/|_|/
#
# 日期：17 Dec 2016
# 版本：v161217
# 日誌:
#     17 Dec 2016
#         * 小優化
#     16 Dec 2016
#         + 重構後第一版（更加靈活適應版本庫的不斷添加、或分支的不同使用情況）
# 説明：
#     所有內容直接複製到 Jenkins 項目的「Execute shell」裏，然後進行以下配置：
#     1. 添加「Choice Parameter」（具體選項可按實際 Git 使用情況列出所需分支）
#        Name: merge_from
#        Choices: develop
#                 release
#                 hotfix
#                 master
#        Description: 請選擇分支合併來源
#     2. 添加「Choice Parameter」（具體選項可按實際 Git 使用情況列出所需分支）
#        Name: merge_to
#        Choices: release
#                 hotfix
#                 master
#        Description: 請選擇分支合併去向（以下供參考）
#                     develop -> release：功能提測後到測試環境進行集成測試
#                     release -> master：測試通過後到（預）生產環境驗收
#                     master -> hotfix：生產緊急 Bug 出現時進行緊急修復
#                     hotfix -> master：緊急 Bug 修復後到（預）生產環境驗收
#     3. 添加「String Parameter」（這裏「hotfix」分支要求來自指定 Tag 或 Commit ID）
#        Name: using_version
#        Description: 請輸入需要使用的 Tag 或 Commit ID）
#                     僅當「merge_to」選擇「hotfix」時需要填寫
#                     （其他情況即使填寫也不起作用）
#     4. 添加「Boolean Parameter」（按實際項目，有多少個版本庫就添加多少項）
#        Name: repo01
#        Description: google/fonts
#     5. 修改下文腳本中「repos」參數（和 4 添加的版本庫一一對應）
#
###############################################################################


# Jenkins 項目上的「Choice Parameter」
if [[ -z ${merge_from} ]]; then
    echo -e "\n[Error] >>> 請選擇分支合併來源「merge_from」\n"
    exit 1
fi

if [[ -z ${merge_to} ]]; then
    echo -e "\n[Error] >>> 請選擇分支合併去向「merge_to」\n"
    exit 1
fi

if [[ ${merge_from} == ${merge_to} ]]; then
    echo -e "\n[Error] >>> 「merge_from」不能與「merge_to」相同\n"
    exit 1
fi

# 暫時除了「hotfix」分支其他都不予刪除
if [[ -z ${del_branch} ]]; then
    del_branch="false"
fi

# Git 版本庫地址（不包括版本庫名稱部分）
git_host="https://user@github.com"

# 關聯數組屬於 Bash 4.0 以上版本的新特性
# 通過「echo $BASH_VERSION」查看 Bash 版本
# 關聯數組需要先聲明再使用
declare -A repos 2>/dev/null || \
    { echo -e "\n[Error] >>> 此處需要使用關聯數組，請升級 Bash 到 4.0 以上版本\n"; exit 1; }

# 存放所有的 Git 版本庫名稱（需要包括所屬組織或用户名）
# 其中「repoxx」同時為 Jenkins 的「Boolean Parameter」，需要一一對應
repos=(
[repo01]="google/fonts"
[repo02]="macvim-dev/macvim"
)

# ${!repos[*]} 為 repos 的所有索引
for key in ${!repos[*]}
do
    if [[ ${!key} == "true" ]]; then
        # 把所有在 Jenkins 上構建項目時選中的版本庫都記錄到「repos_to_use」數組中
        repos_to_use=(${repos_to_use[*]} ${repos[${key}]})
    fi
done
if [[ -z ${repos_to_use[*]} ]]; then
    echo -e "\n[Error] >>> 請選擇需要操作的版本庫\n"
    exit 1
fi


# 函數：版本庫準備（初始化工作區）
# 調用：repo_get_ready "參數1"
#     參數1：版本庫名稱（需要包括所屬組織或用户名）
# 例子：repo_get_ready "google/fonts"
repo_get_ready()
{
    local repo_name=$1
    # 版本庫完整地址
    local git_repo="${git_host}/${git_repo_name}.git"
    # WORKSPACE 是 Jenkins 的系統變量，指向工作目錄
    cd "${WORKSPACE}/${repo_name}" 2>/dev/null || \
        { mkdir -p ${WORKSPACE}/${repo_name}/; cd "${WORKSPACE}/${repo_name}"; }
    if [[ -d ".git" ]]; then
        # 重置到初始狀態以便於直接切換到其他分支
        echo -e "\n[Info] >>> 重置當前工作區到初始狀態"
        git reset --hard HEAD
    else
        echo -e "\n[Info] >>> 首次使用「${repo_name}」，克隆版本庫到本地"
        git clone ${git_repo} ./ || \
            { echo -e "\n[Error] >>> 克隆失敗\n"; exit 1; }
    fi
}


# 函數：合併分支
# 調用：merging_branch "參數1" "參數2" "參數3"
#     參數1：合併的分支來源（也可以是 Tag 或 Commit ID）
#     參數2：合併的分支去向（如分支不存在則直接新增）
#     參數3：合併前是否刪除分支 | [true/false]
# 例子：
merging_branch()
{
    if [[ $# -ne 3 ]]; then
        echo -e "\n[Error] >>> 函數「merging_branch」調用時需要帶三個參數\n"
        exit 1
    fi

    local merge_from=$1
    local merge_to=$2
    local del_branch=$3

    git fetch -p origin

    # 判斷「merge_from」是否是有效的分支名稱（否時當 Tag 或 Commit ID 處理）
    local exist_merge_from=$(git branch -a | egrep -q "origin/${merge_from}$" || echo "false")
    if [[ ${exist_merge_from} != "false" ]]; then
        # 「merge_from」是有效分支則更新分支信息
        git checkout ${merge_from}
        git reset --hard origin/${merge_from}
        git pull origin ${merge_from}
    else
        git checkout ${merge_from} || \
            { echo -e "\n[Error] >>> 無法檢出「${merge_from}」，請確認是否存在\n"; exit 1; }
    fi

    # 「del_branch」等於 true 時表示合併前先刪除「merge_to」分支
    if [[ ${del_branch} == "false" ]]; then
        # 確認遠程是否存在該合併去向的分支
        local exist_merge_to=$(git branch -a | egrep -q "origin/${merge_to}$" || echo "false")
        if [[ ${exist_merge_to} != "false" ]]; then
            git checkout ${merge_to} || \
                { echo -e "\n[Error] >>> 無法檢出「${merge_to}」分支\n"; exit 1; }
            git reset --hard origin/${merge_to}
            git pull origin ${merge_to}
            git merge --no-ff ${merge_from} -m "Merge branch '${merge_from}' into '${merge_to}'" || \
                { echo -e "\n[Error] >>> 無法合併「${merge_from}」到「${merge_to}」分支\n"; exit 1; }
        else
            git checkout -B ${merge_to}
        fi
    elif [[ ${del_branch} == "true" ]]; then
        git branch -D ${merge_to} 2>/dev/null || \
            { echo -e "\n[Info] >>> 本地未有「${merge_to}」分支"; }
        echo -e "\n[Info] >>> 刪除遠程「${merge_to}」分支"
        git push origin --delete ${merge_to} 2>/dev/null || \
            { echo -e "\n[Info] >>> 遠程不存在「${merge_to}」分支"; }
        # 刪除分支後以衍生代替合併操作
        git checkout -B ${merge_to}
    else
        echo -e "\n[Error] >>> 第三個參數值必須為「true」或「false」\n"
        exit 1
    fi

    git push origin ${merge_to} || \
        { echo -e "\n[Error] >>> 無法推送「${merge_to}」分支到遠程版本庫\n"; exit 1; }

    echo -e "\n[Info] >>> 「${merge_from} -> ${merge_to}」合併成功\n\n"
}



if [[ ${merge_to} == "hotfix" ]]; then
    if [[ -z ${using_version} ]]; then
        echo -e "\n[Error] >>> 請輸入需要使用的 Tag 版本或 Commit ID\n"
        exit 1
    fi
    # 「hotfix」分支來自指定的 Tag 或 Commit ID 版本
    merge_from=${using_version}
    # 「hotfix」分支每次使用前都刪除舊分支
    del_branch="true"
fi

# 用於計算版本庫個數
count=0
for repo_name in ${repos_to_use[*]}
do
    let count+=1
    # ${#repos_to_use[*]} 獲取數組元素個數
    echo -e "\n[Info] >>> [${count}/${#repos_to_use[*]}] 開始更新版本庫「${repo_name}」"
    # 函數：版本庫準備（初始化工作區）
    repo_get_ready ${repo_name}
    # 函數：合併分支
    merging_branch "${merge_from}" "${merge_to}" "${del_branch}"
done

