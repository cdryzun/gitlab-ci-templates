#!/bin/sh

IFS='
'

# Get vault path from secrets directly injected into corresponding variables
for secret in `for i in $(ls vars/vault.*);do
	 cat $i|grep '#\*'|egrep -v '^#'
done|sort|uniq`;do

	# Get variable name based on vault path
	value=$(echo "$secret"|awk '{print $2}')
	for files in $(ls vars/vault.*);do
		key=$(grep -B 1 -B 1 ${value} ${files}|sed "s#--##g"|sort -r|uniq|head -n 1|awk -F ":" '{print $1}'|sed "s# ##g")
	done

	# Get vault key & vault key path, but vault key path cannot be directly used by vault cli yet, needs processing
	#echo "${key} ${value}"

	# Process vault key path to be directly usable by vault cli, example result
	# vault kv get -field=QUANTEX_PAAS secrets/infrastructure/k8s
	field=$(echo ${value##*/}|awk -F '@' '{print $1}')
	vaultPath=$(echo ${value}|awk -F "${field}@" '{print $2"/"$1}')

	# Write vault path content to key name file for terraform to reference
	vault kv get -field=${field} ${vaultPath} > terraform/${key}.vault
done