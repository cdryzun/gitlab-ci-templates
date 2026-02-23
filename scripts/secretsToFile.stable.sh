#!/bin/sh

IFS='
'

# 获取 secrets 直接注入在对应变量中的 vault path
for secret in `for i in $(ls vars/vault.*);do
	 cat $i|grep '#\*'|egrep -v '^#' 
done|sort|uniq`;do
	
	# 根据 vault path 获取 变量名称
	value=$(echo "$secret"|awk '{print $2}')
	for files in $(ls vars/vault.*);do
		key=$(grep -B 1 -B 1 ${value} ${files}|sed "s#--##g"|sort -r|uniq|head -n 1|awk -F ":" '{print $1}'|sed "s# ##g")
	done

	# 得到 vault key & vault key path，但由于 vault key path 目前还不能直接提供给 vault cli 直接使用，需要做一层处理
	#echo "${key} ${value}"

	# 处理 vault key path 能够直接被 vault cli 直接使用, 示例结果
	# vault kv get -field=QUANTEX_PAAS secrets/infrastructure/k8s
	field=$(echo ${value##*/}|awk -F '@' '{print $1}')
	vaultPath=$(echo ${value}|awk -F "${field}@" '{print $2"/"$1}')

	# 将 vault path 中的内容写入至 key name 的文件中，提供给后续 terraform 进行引用
	vault kv get -field=${field} ${vaultPath} > terraform/${key}.vault
done