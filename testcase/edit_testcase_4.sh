# 定义目标文件、源文件和要查找的字符串
target_file=$1
source_file="set_iotv2.txt"
search_string="dn_metric_reporter_list"

# 使用awk命令进行插入操作
awk -v search="$search_string" -v source_file="$source_file" '
BEGIN { RS="\n"; FS=""; }
{
    if ($0 ~ search) {
        # 打印源文件内容
        while ((getline line < source_file) > 0)
            print line;
        # 打印目标文件中找到的特定字符串前的行
        print $0;
    } else {
        print $0;
    }
}
' $target_file > temp_file.txt && mv temp_file.txt $target_file
