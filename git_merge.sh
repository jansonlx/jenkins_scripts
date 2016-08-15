#!/bin/bash -e

###############################################################################
# 腳本：Merge Branch via Jenkins
# 功能：合併指定分支到特定分支
# 作者：
#      ____ __   __  __ _____ ___  __  __
#     /_  /  _ \/ / / / ____/ __ \/ / / /
#      / / /_/ / /|/ /_/_  / / / / /|/ /
#   __/ / /-/ / / | /___/ / /_/ / / | /
#  /___/_/ /_/_/|_|/_____/\____/_/|_|/
#
# 日期：14 Aug 2016
# 版本：2.0
# 更新日誌:
#     14 Aug 2016
#         + 重構：獨立版本庫，不依賴於其他
#     27 Jun 2016
#         + 第一版
# 使用説明：
#     在 Jenkins 上新增構建項目前的可選菜單。
#     其中 Choice Parameter 有：
#         repo_name：選擇需要操作的 Git 版本庫
#             選項：列出可操作的 Git 版本庫
#         merge_path：分支合併去向
#             選項：
#                 develop -> release
#                 release -> master
#                 master -> hotfix
#                 hotfix -> master
#    Boolean Parameter 有：
#        delete_branch：〔選填〕是否刪除「release」分支
#                       僅作用於「merge_path」選擇「develop -> release」時
#    String Parameter 有：
#        using_version：〔選填〕需要修復的版本，默認使用最新的 Tag 版本
#                       僅作用於「merge_path」選擇「master -> hotfix」時
#                       可輸入 Tag 或 Hash ID
#    merge_path 選項解釋：
#        develop -> release：开发提测后代码上 release 进行功能集成测试
#        release -> master：版本测试后代码上 master 进行（预）生产环境验收
#        master -> hotfix：线上紧急 Bug 出现时代码上 hotfix 进行紧急修复
#        hotfix -> master：紧急 Bug 修复后代码上 master 进行（预）生产环境验收
#
###############################################################################


if [[ -z ${repo_name} ]]; then
    echo -e "\n***** 請選擇需要操作的 Git 版本庫「repo_name」 *****\n"
    exit 1
fi

# merge_path - 分支合併去向，選項包括：
#   develop -> release
#   release -> master
#   master -> hotfix
#   hotfix -> master
if [[ -z ${merge_path} ]]; then
    echo -e "\n***** 請選擇分支合併去向「merge_path」 *****\n"
    exit 1
fi

# Git 版本庫地址（不包括版本庫名稱部分）
git_host="https://user@github.com/user/"


# 函數：合併前的版本庫準備
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


# 函數：合併 develop 分支到 release
# 參數：$1 - delete_branch - 無或 false 代表不刪除 release 分支
merge_develop_into_release()
{
    if [[ -z $1 ]]; then
        # 默認不刪除 release 分支
        delete_branch=false
    else
        delete_branch=$1
    fi
    echo "***** 即將合併「develop」分支到「release」分支 *****"
    git fetch origin
    git checkout develop
    git pull origin develop
    echo "***** 刪除本地「release」分支 *****"
    git branch -D release 2>/dev/null || { echo -e "***** 本地未有「release」分支 *****\n"; }
    exists_release=`git branch -a | grep "origin/release" 2>/dev/null || echo "false"`
    if [[ ${exists_release} != "false" ]]; then
        if [[ ${delete_branch} == "true" ]]; then
            echo "***** 刪除遠程「release」分支 *****"
            git push origin --delete release 2>/dev/null || { echo "***** 遠程未有「release」分支 *****"; }
            git checkout -B release
        else
            git checkout release
            git pull origin release
            git merge --no-ff develop -m "Merge branch 'develop' into 'release'" || { echo -e "***** [ERROR] 無法合併「develop」到「release」分支 *****\n"; exit 1; }
        fi
    else
        git checkout -B release
    fi
    git push origin release || { echo -e "***** [ERROR] 無法推送「release」分支到遠程版本庫 *****\n"; exit 1; }
    echo -e "***** 分支合併成功 *****\n"
}


# 函數：合併 release 分支到 master
merge_release_into_master()
{
    echo "***** 即將合併「release」分支到「master」分支 *****"
    git fetch origin
    git checkout release
    git pull origin release
    git checkout master
    git pull origin master
    git merge --no-ff release -X theirs -m "Merge branch 'release' into 'master'" || { echo -e "***** [ERROR] 無法合併「release」到「master」分支 *****\n"; exit 1; }
    git push origin master || { echo -e "***** [ERROR] 無法推送「master」分支到遠程版本庫 *****\n"; exit 1; }
    echo -e "***** 分支合併成功 *****\n"
}


# 函數：合併 master 分支到 hotfix
# 參數：$1 - using_version 需要修復的版本 - 默認使用最新 tag 分支
merge_master_into_hotfix()
{
    echo "***** 即將合併「master」分支到「hotfix」分支 *****"
    git fetch origin
    if [[ -z $1 ]]; then
        using_version=`git tag -l "v*" | sed -n '$p'`
        if [[ -z ${using_version} ]]; then
            using_version="master"
        fi
    else
        using_version=$1
    fi
    git checkout master
    git pull origin master
    echo "***** 刪除本地「hotfix」分支 *****"
    git branch -D hotfix 2>/dev/null || { echo -e "***** 本地未有「hotfix」分支 *****\n"; }
    echo "***** 刪除遠程「hotfix」分支 *****"
    git push origin --delete hotfix 2>/dev/null || { echo "***** 遠程未有「hotfix」分支 *****"; }
    git checkout -B hotfix ${using_version} || { echo -e "***** [ERROR] 請檢查「using_version」參數 *****\n"; exit 1; }
    git push origin hotfix || { echo -e "***** [ERROR] 無法推送「hotfix」分支到遠程版本庫 *****\n"; exit 1; }
    echo "***** 「hotfix」分支衍生自「${using_version}」 *****"
    echo -e "***** 分支合併成功 *****\n"
}


# 函數：合併 hotfix 分支到 master
merge_hotfix_into_master()
{
    echo "***** 即將合併「hotfix」分支到「master」分支 *****"
    git fetch origin
    git checkout hotfix
    git pull origin hotfix
    git checkout master
    git pull origin master
    git merge --no-ff hotfix -X theirs -m "Merge branch 'hotfix' into 'master'" || { echo -e "***** [ERROR] 無法合併「hotfix」到「master」分支 *****\n"; exit 1; }
    git push origin master || { echo -e "***** [ERROR] 無法推送「master」分支到遠程版本庫 *****\n"; exit 1; }
    echo -e "***** 分支合併成功 *****\n"
}


# 函數：選擇分支合併方案
# 參數：$1 - merge_path - 分支合併方案
#       $2 - delete_branch - 是否刪除分支（僅作用於 -> release）
#       $3 - using_version - 需要修復的版本（僅作用於 -> hotfix）
merge_path_choose()
{
    if [[ $# -eq 1 ]]; then
        merge_path=$1
    elif [[ $# -eq 2 ]]; then
        merge_path=$1
        delete_branch=$2
    elif [[ $# -eq 3 ]]; then
        merge_path=$1
        delete_branch=$2
        using_version=$3
    else
        echo "***** [ERROR] 「merge_path_choose」函數的參數個數有誤 *****"
        exit 1
    fi
    # develop -> release
    if [[ ${merge_path} == "develop -> release" ]]; then
        if [[ -n ${delete_branch} ]]; then
            merge_develop_into_release "${delete_branch}"
        else
            merge_develop_into_release
        fi
    # master -> hotfix
    elif [[ ${merge_path} == "master -> hotfix" ]]; then
        if [[ -n ${using_version} ]]; then
            merge_master_into_hotfix "${using_version}"
        else
            merge_master_into_hotfix
        fi
    # release -> master
    elif [[ ${merge_path} == "release -> master" ]]; then
        merge_release_into_master
    # hotfix -> master
    elif [[ ${merge_path} == "hotfix -> master" ]]; then
        merge_hotfix_into_master
    fi
}



if [[ ${repo_name} == "所有" || ${repo_name} == "first-repo-name" ]]; then
    repo_get_ready "first-repo-name"
    merge_path_choose "${merge_path}" "${delete_branch}" "${using_version}"
fi
if [[ ${repo_name} == "所有" || ${repo_name} == "second-repo-name" ]]; then
    repo_get_ready "second-repo-name"
    merge_path_choose "${merge_path}" "${delete_branch}" "${using_version}"
fi

