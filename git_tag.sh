#!/bin/bash -e

###############################################################################
# 腳本：Tag Released Version via Jenkins
# 功能：為上線後的版本添加標籤
# 作者：
#        ____ __   __  __ _____ ___  __  __
#       /_  /  _ \/ / / / ____/ __ \/ / / /
#        / / /_/ / /|/ /_/_  / / / / /|/ /
#     __/ / /-/ / / | /___/ / /_/ / / | /
#    /___/_/ /_/_/|_|/_____/\____/_/|_|/
#
# 日期：16 Dec 2016
# 版本：v161216
# 日誌:
#     16 Dec 2016
#         + 重構後第一版（更加靈活適應版本庫的不斷添加）
# 説明：
#     所有內容直接複製到 Jenkins 項目的「Execute shell」裏，然後進行以下配置：
#     1. 添加「String Parameter」
#        Name: tag_name
#        Description: Git 標籤名稱
#                     要求類似：v1.2.0 / v2.3.5
#     2. 添加「String Parameter」
#        Name: tag_comment
#        Description: Git 標籤説明
#                     建議填寫更新的內容，以供後續參考
#     3. 添加「Boolean Parameter」（按實際項目，有多少個版本庫就添加多少項）
#        Name: repo01
#        Description: google/fonts
#     4. 修改下文腳本中「repos」參數（和 3 添加的版本庫一一對應）
#
###############################################################################


# Jenkins 項目上的「String Parameter」
if [[ -z ${tag_name} ]]; then
    echo -e "\n[Error] >>> 請填寫 Git 標籤名稱「tag_name」\n"
    exit 1
fi

if [[ -z ${tag_comment} ]]; then
    echo -e "\n[Error] >>> 請填寫 Git 標籤説明「tag_comment」\n"
    exit 1
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

repos_to_use=()
# ${!repos[*]} 為 repos 的所有索引
for key in ${!repos[*]}
do
    if [[ ${!key} == "true" ]]; then
        # 把所有在 Jenkins 上構建項目時選中的版本庫都記錄到「repos_to_use」數組中
        repos_to_use=(${repos_to_use[*]} ${repos[${key}]})
    fi
done
if [[ -z ${repos_to_use[*]} ]]; then
    echo -e "\n[Error] >>> 請選擇需要添加標籤的版本庫\n"
    exit 1
fi

valid_tag_name=$(echo "${tag_name}" | egrep '^v[0-9]+\.[0-9]+\.[0-9]+$' || echo "false")
if [[ ${valid_tag_name} == "false" ]]; then
    echo -e "\n[Error] >>> 標籤名稱「tag_name」要求格式類似：「v12.34.56」\n"
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
    local git_repo="${git_host}/${repo_name}.git"
    # WORKSPACE 是 Jenkins 的系統變量，指向工作目錄
    # 如同時用到了「Git Merge」那個 Jenkins 項目，
    # 可以考慮使用同個工作目錄以避免重複 clone 了那麼多個版本庫
    # 具體做法是用對應的工作目錄絕對路徑代替「WORKSPACE」
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


# 函數：添加標籤
# 調用：git_tag "參數1" "參數2"
#     參數1：標籤名稱
#     參數2：標籤説明
# 例子：git_tag "v1.0.0" "第一個穩定版本上線"
git_tag()
{
    if [[ $# -eq 2 ]]; then
        local tag_name=$1
        local tag_comment=$2
    else
        echo -e "\n[Error] >>> 「git_tag」函數的參數個數有誤\n"
        exit 1
    fi

    echo -e "\n[Info] >>> 將在「master」分支的最新提交上添加標籤"

    git fetch -p origin

    # 確認標籤是否已存在
    local valid_tag_name=`git tag -l "v*" | egrep "${tag_name}" || echo "true"`
    if [[ ${valid_tag_name} != "true" ]]; then
        echo -e "\n[Error] >>> 標籤名稱「${tag_name}」已存在\n"
        exit 1
    fi

    git checkout master
    git pull origin master
    git tag -a ${tag_name} -m "${tag_comment}" || \
        { echo -e "\n[Error] >>> 無法添加標籤「${tag_name}」\n"; exit 1; }
    git push origin ${tag_name} || \
        { echo -e "\n[Error] >>> 無法推送標籤「${tag_name}」\n"; exit 1; }
    echo -e " 标签添加成功 *****"
    echo -e "\n[Info] >>> 標籤「${tag_name}」添加成功\n\n"
}



# 用於計算版本庫個數
count=0
for repo_name in ${repos_to_use[*]}
do
    let count+=1
    # ${#repos_to_use[*]} 獲取數組元素個數
    echo -e "\n[Info] >>> [${count}/${#repos_to_use[*]}] 開始更新版本庫「${repo_name}」"
    # 函數：版本庫準備（初始化工作區）
    repo_get_ready ${repo_name}
    # 函數：添加標籤
    git_tag "${tag_name}" "${tag_comment}"
done

