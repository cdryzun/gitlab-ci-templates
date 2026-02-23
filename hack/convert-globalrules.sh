
CUT_FILE='utils/rules.stable.gitlab-ci.yml'
OUT_FILE='templates/global-rules.yml'

> ${OUT_FILE}

sed -n -e '/^\.release_version: &release_version/,/^$/p' ${CUT_FILE} >> ${OUT_FILE}

sed -n -e '/^\.default_trigger_vars: &default_trigger_vars/,/^$/p' ${CUT_FILE} >> ${OUT_FILE}

sed -n -e '/\.trigger_rule:/,/^$/p'  ${CUT_FILE} | sed 's#.trigger_rule:#workflow:#g' |grep -v '^$' >> ${OUT_FILE}

sed -n -e '/^\.master_schedule_manual_trigger:/,/^$/p' ${CUT_FILE}| sed '1,2d' >> ${OUT_FILE}

sed -i 's#manual#always#g' ${OUT_FILE}