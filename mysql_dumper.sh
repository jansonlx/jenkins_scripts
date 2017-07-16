#!/bin/bash -e
#
# 用於 MySQL 數據庫備份
#
# 建議加入 crontab 定時任務中，具體操作：
#    1. 編輯 crontab 任務列表
#       crontab -e
#    2. 在任務列表底部添加以下內容（實現每週一、四 1 a.m. 執行此腳本）
#       0 1 * * 1,4 cd [本文件所在路徑] && ./[本文件名稱(.sh)]
#
# Janson, 16 Jul 2017


### 基礎配置 ###

# 數據庫登入用戶（注意權限）
db_user="user"
# 數據庫登入密碼
db_password="password"
# 數據庫連接主機
db_host="127.0.0.1"
# 數據庫連接端口
db_port="3306"

# 括號內填入需要備份的數據庫名稱，多個數據庫時以空格區分
# 如指定多個數據庫，則忽略 dump_table_list 變量
dump_db_list=(db_name_01 db_name02)
# 括號內填入需要備份的數據表名稱，多個數據表以空格區分
dump_table_list=(tbl_name_01 tbl_name_02)
# 括號內填入 mysqldump 的選項，多個選項以空格區分
# 常用：
#     -d 不導出表數據
#     -t 不生成建表語句
#     -R 導出存儲過程和自定義函數
#                注意：使用此選項後導出和導入所需權限較高
mysqldump_options=()
# 是否重置自增字段初始值（即去除「AUTO_INCREMENT=xxx」語句）
# true 即重置
if_reset_auto_incre="true"

# 備份文件存放路徑
dump_path="/path/to/save"
# 備份文件名稱
dump_file="$(date +'%y%m%d_%H%M%S').sql"
# 備份文件名稱前綴（統一文件名稱以便在清除歷史數據時降低誤刪風險）
# 未設置，清除備份歷史時，處理「dump_path」根目錄下所有文件
# 設置後，清除備份歷史時，僅處理以「dump_file_prefix」的值開頭的文件
dump_file_prefix="db_dump_"

# 是否清除備份歷史文件
# true 即清除
# 刪除操作有風險，請謹慎選擇，且建議設置「dump_file_prefix」變量
if_del_history="true"
# 清除歷史文件時保留的備份文件個數
keep_file_total=20


### 業務處理 ###

# 函數：獲取備份目標（數據庫或表）
# 參數：〔無需傳入〕
function get_dump_target
{
    # 判斷指定的數據庫個數，大於 1 時指定同時備份多個數據庫
    if [[ "${#dump_db_list[*]}" -gt 1 ]]; then
        echo "--databases ${dump_db_list[*]}"
    # 指定的數據庫個數等於 1 時需要再判斷指定的數據表
    elif [[ "${#dump_db_list[*]}" -eq 1 ]]; then
        # 判斷指定的數據表個數，大於 0  代表同時備份多個數據表
        if [[ "${#dump_table_list[*]}" -gt 0 ]]; then
            echo "${dump_db_list[0]} ${dump_table_list[*]}"
        # 未指定數據表時，僅返回指定的數據庫
        else
            echo "${dump_db_list[0]}"
        fi
    # 未指定數據庫時，代表導出所有數據庫
    else
        echo "--all-databases"
    fi
}

# 函數：日誌輸出前顯示當下時間和日誌類型
# 參數：日誌類型（自定義，如 ERROR|INFO）
function log_prefix
{
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$1]"
}


if [[ "${dump_path}" ]]; then
    cd "${dump_path}" 2>/dev/null || \
    mkdir -p "${dump_path}" && cd "${dump_path}"
    echo -e "$(log_prefix INFO) 進入數據庫備份目錄 => ${dump_path}\n" 
else
    echo "$(log_prefix ERROR) 必需指定數據庫備份文件存放路徑「dump_path」"
    exit 1
fi

echo -e "$(log_prefix INFO) 數據庫備份中......\n"

# 下面語句中，get_dump_target 和 mysqldump_options 變量不可加引號
mysqldump $(get_dump_target) -h "${db_host}" -P "${db_port}" -u "${db_user}" \
-p"${db_password}" ${mysqldump_options[*]} > "${dump_file_prefix}${dump_file}" || { \
# 當 dump_into_file 指定的文件路徑不存在時，「|| :」實現讓其顯示報錯信息而不退出
mv "${dump_file_prefix}${dump_file}" "${dump_file_prefix}${dump_file}.incomplete" || :; \
echo -e "\n$(log_prefix ERROR) 數據庫導出報錯，\
如有生成備份文件「${dump_path}/${dump_file_prefix}${dump_file}.incomplete」，其內容可能不完整"; \
exit 1; }

# 僅當 if_reset_auto_incre 設置爲 true 時執行以下邏輯
if [[ "${if_reset_auto_incre}" == "true" ]]; then
    echo -e "$(log_prefix INFO) 重置自增字段初始值\
（即去除「AUTO_INCREMENT=xxx」語句）\n"
    sed -i "s/AUTO_INCREMENT=[0-9]\+\s//g" "${dump_file_prefix}${dump_file}"
fi

# 僅當 if_del_history 設置爲 true 時執行以下邏輯
if [[ "${if_del_history}" == "true" ]]; then
    echo -e "$(log_prefix INFO) 刪除歷史數據\
（按文件修改時間保留最近 ${keep_file_total} 份數據）\n"
    # 僅刪除同級目錄下的文件（不處理文件夾）
    # -I {} 用於處理文件名含有空格的情況（否則存在誤刪漏刪的情況）
    ls -tp | grep -E "^${dump_file_prefix}.*[^/]$" | \
    awk -v keep_total="${keep_file_total}" '{if(NR>keep_total) print}' | \
    xargs -I {} rm -f {}
fi

echo "$(log_prefix INFO) 數據庫備份完成〔${dump_path}/${dump_file_prefix}${dump_file}〕"
