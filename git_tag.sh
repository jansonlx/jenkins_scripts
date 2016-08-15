#!/bin/bash -e

###############################################################################
# 腳本：Tag Released Version via Jenkins
# 功能：為上線後的版本添加標籤
# 作者：
#      ____ __   __  __ _____ ___  __  __
#     /_  /  _ \/ / / / ____/ __ \/ / / /
#      / / /_/ / /|/ /_/_  / / / / /|/ /
#   __/ / /-/ / / | /___/ / /_/ / / | /
#  /___/_/ /_/_/|_|/_____/\____/_/|_|/
#
# 日期：15 Aug 2016
# 版本：2.0
# 更新日誌:
#     15 Aug 2016
#         + 重構：獨立版本庫，不依賴於其他
#     27 Jun 2016
#         + 第一版
# 使用説明：
#     在 Jenkins 上新增構建項目前的可選菜單。
#     其中 Choice Parameter 有：
#         repo_name：選擇需要操作的 Git 版本庫
#             選項：列出可操作的 Git 版本庫
#    String Parameter 有：
#        tag_name：Git 標籤名稱
#                  建議：v1.2.0 / v2.3.5
#        tag_comment：〔選填〕標籤説明
#                     默認值為「Tag released version '${tag_name}'」
#
###############################################################################


# Git 版本庫地址（不包括版本庫名稱部分）
git_host="https://user@github.com/user/"

if [[ -z ${repo_name} ]]; then
    echo -e "\n***** [ERROR] 請選擇需要操作的 Git 版本庫「repo_name」 *****\n"
    exit 1
fi

if [[ -z ${tag_name} ]]; then
    echo -e "\n***** [ERROR] 請填寫標籤名稱「tag_name」 *****\n"
    exit 1
fi

valid_tag_name=`echo "${tag_name}" | egrep '^v[0-9]+\.[0-9]+\.[0-9]+$' || echo "false"`
if [[ ${valid_tag_name} == "false" ]]; then
    echo -e "\n***** [ERROR] 標籤名稱「tag_name」要求格式類似：「v12.34.56」 *****\n"
    exit 1
fi

if [[ -z ${tag_comment} ]]; then
    # 標籤默認説明
    tag_comment="Tag released version '${tag_name}'"
fi


# 函數：版本庫準備
# 參數：$1 - git_repo_name - 版本庫名稱
repo_get_ready()
{
    git_repo_name=$1
    git_repo="${git_host}/${git_repo_name}.git"
    echo -e "\n***** 準備「${git_repo_name}」版本庫 *****"
    cd ${git_repo_name}/ 2>/dev/null || { mkdir ${git_repo_name}/; cd ${git_repo_name}; }
    if [[ -d ".git" ]]; then
        # 切換其他分支之前必需還原對當前工作區的所有更改
        echo -e "***** 還原對當前工作區的所有更改 *****"
        # 獲取當前分支名稱
        current_branch=`git branch | sed -n "s/^\*[ ]*\([^ ]\{1,\}\)$/\1/p"`
        if [[ -z ${current_branch} ]]; then
            git reset --hard HEAD
        else
            git reset --hard origin/${current_branch}
        fi
        echo -e "***** 還原成功 *****\n"
    else
        echo -e "***** 首次使用「${git_repo_name}」，克隆版本庫到本地 *****"
        git clone ${git_repo} ./ || { echo -e "***** [ERROR] 克隆失敗 *****\n"; exit 1; }
        echo -e "***** 克隆成功 *****\n"
    fi
}


# 函數：添加及推送標籤
# 參數：$1 - tag_name - 標籤名稱
#       $2 - tag_comment - 標籤説明
git_tag()
{
    if [[ $# -eq 2 ]]; then
        tag_name=$1
        tag_comment=$2
    else
        echo "***** [ERROR] 「git_tag」函數的參數個數有誤 *****"
        exit 1
    fi
    echo -e "\n***** 將在「master」分支的最新提交上打標籤 *****"
    git fetch origin
    # 確認標籤是否已存在
    valid_tag_name=`git tag -l "v*" | egrep "${tag_name}" || echo "true"`
    if [[ ${valid_tag_name} != "true" ]]; then
        echo -e "\n***** [ERROR] 標籤名稱「${tag_name}」已存在 *****\n"
        exit 1
    fi
    git checkout master
    git pull origin master
    git tag -a ${tag_name} -m "${tag_comment}" || { echo -e "***** [ERROR] 無法添加標籤「${tag_name}」 *****\n"; exit 1; }
    git push origin ${tag_name} || { echo -e "***** [ERROR] 無法推送標籤「${tag_name}」 *****\n"; exit 1; }
    echo "***** 标签添加成功 *****"
}



if [[ ${repo_name} == "所有" || ${repo_name} == "first-repo-name" ]]; then
    repo_get_ready "first-repo-name"
    git_tag "${tag_name}" "${tag_comment}"
fi
if [[ ${repo_name} == "所有" || ${repo_name} == "second-repo-name" ]]; then
    repo_get_ready "second-repo-name"
    git_tag "${tag_name}" "${tag_comment}"
fi

