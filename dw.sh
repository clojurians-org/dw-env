####################################
# larluo 
# 2018-09-25 CREATE
###################################
set -e
help_message="$0 <extract :id :path|load :id :path|transform :id>"

my=$(cd -P -- "$(dirname -- "${BASH_SOURCE-$0}")" > /dev/null && pwd -P); cd $my
if [ -e ${my}/dw.conf/env.sh ]; then . ${my}/dw.conf/env.sh; fi
dw_data=${dw_data:-${my}/nix.var/data_in}
echo "[info] dw_data: ${dw_data}"

full_action=$1; id=$2
my_monitor=${my}/nix.var/monitor
id_data=${my}/nix.var/data/${id}
id_log=${my}/nix.var/log/${id}
dw_action=$(echo $full_action | cut -d: -f1)

mkdir -p ${my_monitor} ${id_data} ${id_log}

inotifywait_cmd=${my}/dw.sh.out/inotify-tools-3.14/src/inotifywait
if [ "$dw_action" == "extract" ]; then
  if [ "$3" != "--input" ]; then echo "--input is missing" && exit 0; fi
  if [ "$4" == "" ]; then echo "[ERROR] --input is empty!" && exit 1; fi
  extract_id="$2"
  extract_input="$4"
  
  echo "[info-$full_action] watchiing ok file from ${extract_input} to extract..."
  ${inotifywait_cmd} -e create -e moved_to -m "${extract_input}" |
    while read path action file; do
      ts=$(date --iso-8601=seconds)
      echo "[info-${ts}] file created: ${path}${file}"
      if [[ "$file" =~ .*\.ok$  ]]; then
        in_file=$(basename "$file" ".ok")
        mkdir -p "${dw_data}/${extract_id}/${ts}"
        echo mv "${path}${in_file}" "${dw_data}/${extract_id}/${ts}"
        mv "${path}${in_file}" "${dw_data}/${extract_id}/${ts}"
        rm -rf "${path}${file}"
      fi
    done
elif [ "$dw_action" == "load" ]; then
  load_method=$(echo $full_action | cut -d: -f2)
  if [ "$3" != "--extract-id" ]; then echo "[INFO] --extract-id is missing!" && exit 0; fi
  if [ "$4" == "--connect-id" ]; then echo "[ERROR] --extract-id is empty!" && exit 1; fi
  if [ "$5" != "--connect-id" ]; then echo "[INFO] --connect-id is missing" && exit 0; fi
  if [ "$6" == "--input" ]; then echo "[ERROR] --connect-id is empty!" && exit 0; fi
  if [ "$7" != "--input" ]; then echo "[INFO] --input is missing" && exit 0; fi
  if [ "$8" == "--format" ]; then echo "[ERROR] --input is empty!" && exit 0; fi
  if [ "$9" != "--format" ]; then echo "[ERROR] --format is missing!" && exit 0; fi
  if [ "$10" == "" ]; then echo "[ERROR] --format is empty!" && exit 0; fi
  full_load_id="$2"; extract_id="$4"; connect_id="$6"; load_input="$8"; format="${10}"
  load_id=$(echo $full_load_id | cut -d: -f1)
  load_id_type=$(echo $full_load_id | cut -d: -f2)

  # ======== DYNAMIC SQL GENERATOR AREA ========

  if [[ "$format" == @* ]] ; then
    stg_sqlldr=$(echo "$format" | cut -c2- | xargs cat)
  else
    format_delimiter=$(echo $format | cut -d\| -f1)
    format_columns=$(echo $format | cut -d\| -f2)
    ods_table=$(echo ${load_id} | cut -d- -f1)
    stg_table=stg_${ods_table}
    all_columns=$(echo $format_columns | sed 's/://g')
    all_src_columns=$(printf ",${all_columns}" | sed 's/,/,s./g' | cut -c2-)
    stg_ddl="CREATE TABLE ${stg_table} (\n$(printf "${all_columns}" | awk 'BEGIN {RS=","} {print ", "$0"  VARCHAR2(255)"}' | sed '1s/,/ /')\n);"
    ods_ddl="CREATE TABLE ${ods_table} (\n$(printf "${all_columns}" | awk 'BEGIN {RS=","} {print ", "$0"  VARCHAR2(255)"}' | sed '1s/,/ /')\n);"
    ods_join_part=$(printf ${format_columns} | awk 'BEGIN {RS=","} /:/{printf "AND S."$0"=D."$0" "}' | cut -c5- | sed 's/://g')
    ods_set_part=$(printf ${format_columns} | awk 'BEGIN {RS=","} !/:/{printf ", D."$0"=S."$0}' | cut -c3-)
    ods_merge_sql="MERGE INTO ${ods_table} D\n USING ${src_table} S ON (${ods_join_part}) \nWHEN MATCHED THEN\nUPDATE SET \n${ods_set_part}\nWHEN NOT MATCHED THEN\nINSERT (${all_columns}) VALUES(${all_src_columns})"

    stg_sqlldr="LOAD DATA\nCHARACTERSET  AL32UTF8\nINFILE '${path}${file}'\nTRUNCATE INTO TABLE ${stg_table}\nFIELDS TERMINATED BY '${format_delimiter}'\nTRAILING NULLCOLS (\n${all_columns}\n)"
  fi
  if [ "${load_id_type}" == "oracle" ]; then
    dw_connect__oracle=${dw_connect__oracle:-${my}/dw.conf/connect.oracle}
    stg_connect_id=$(echo $connect_id | cut -d, -f1)
    ods_connect_id=$(echo $connect_id | cut -d, -f2)
    stg_connect=$(grep "$stg_connect_id" "$dw_connect__oracle" | cut -d= -f2- | base64 -d)
    ods_connect=$(grep "$ods_connect_id" "$dw_connect__oracle" | cut -d= -f2- | base64 -d)
    echo -e "============ ORACLE SQL GENRATOR ============\n"
    echo -e "--> oracle.connnect: ${stg_connect}->${ods_connect}"
    if [ "$stg_ddl" != "" ]; then 
      echo -e "------------ stg_ddl.start ------------\n${stg_ddl}"; 
      echo -e "------------ std_ddl.end ------------\n\n"
    fi
    if [ "$ods_ddl" != "" ]; then 
      echo -e "------------ stg_ddl.start ------------\n${stg_ddl}"; 
      echo -e "------------ ods.ddl.end ------------\n\n"
    fi
    echo -e "------------ stg_sqlldr.start ------------\n${stg_sqlldr}"
    echo -e "------------ stg_sqlldr.end------------\n\n"

    if [ "$ods_merge_sql" != "" ]; then 
      echo -e "------------ ods_merge_sql.start ------------\n${ods_merge_sql}"
      echo -e "------------ ods_merge_sql.end------------\n\n"
    fi
  elif [ "${load_id_type}" == "postgresql" ]; then
    echo "[INFO] load postgresql ..." 
  else
    echo "[ERROR] UNSUPPORTED LOAD TYPE: $load_id_type" && exit 1
  fi

  # ======== LOAD ACTION AREA ========
  echo  "[info-$full_action] watching pattern[${load_input}] from extract_id: ${extract_id} to load ${load_id}..."
  ${inotifywait_cmd} -e create -e moved_to -m "${dw_data}/${extract_id}" |
    while read path action file; do
      ts=$(date --iso-8601=seconds)
      id_data_ts=${id_data}/${ts}
      id_log_ts=${id_log}/${ts}
      echo "[info-${ts}] file created: ${path}${file}"
      if [ -e  "${path}${file}"/${load_input} ]; then
        mkdir -p ${id_data_ts} ${id_log_ts}
        if [ "${load_id_type}" == "oracle" ]; then
          export NLS_LANG=AMERICAN_AMERICA.UTF8
          echo "[INFO] ============ a. loading oracle stg table ============"
          echo "${stg_sqlldr}" > ${id_data_ts}/${id}.ctl
          echo "sqlldr userid=${stg_connect} control=${id_data_ts}/${id}.ctl data=${path}${file}/${load_input} bad=${id_data_ts}/${id}.bad direct=true errors=0  log=${id_log_ts}/${id}.log"
          set +e
          sqlldr userid=${stg_connect} control=${id_data_ts}/${id}.ctl data=${path}${file}/${load_input} bad=${id_data_ts}/${id}.bad direct=true errors=0  log=${id_log_ts}/${id}.log
          if [ $! != 0 ]; then
            echo fail.${path}/${file}/${load_input} > ${my_monitor}/${id}.${ts}.fail
            echo "[ERROR] ============ a. oracle stg table load fail! >>>> ${id_data_ts}/${id}.log ============"
            cat ${id_data_ts}/${id}.log
            continue
          fi
          set -e
          
          PR_ID=$(echo ${id} | sed s'/^T_/PR_/')
          echo "[INFO] ============ b. transform oracle ods table [${PR_ID}]============"
# HERE-DOC START
          sqlplus -s ${ods_connect} <<EOF
            SET FEEDBACK OFF 
            SET PAGESIZE 0
            SET SERVEROUTPUT ON
            SELECT TEXT FROM USER_SOURCE WHERE NAME = '${PR_ID}' ORDER BY LINE;
          
            WHENEVER SQLERROR EXIT 1
            DECLARE 
              P_DATA_DATE VARCHAR2(10) := '00000000' ;
              P_O_RESULT VARCHAR2(32767) ;
            BEGIN
              ${PR_ID}(P_DATA_DATE, P_O_RESULT) ;
            EXCEPTION
              WHEN OTHERS THEN
                -- DBMS_OUTPUT.PUT_LINE('----> [ERROR]-P_O_RESULT:[' || P_O_RESULT || ']');
                RAISE ;
            END ;
            /
EOF
# HERE-DOC END
          if [ $? != 0 ]; then
            echo fail.${path}/${file}/${load_input} > ${my_monitor}/${id}.${ts}.fail
            echo "[ERROR] ============ a. oracle stg table load fail! >>>> ${id_data_ts}/${id}.log ============"
            continue
          fi
          echo success.${path}/${file}/${load_input} > ${my_monitor}/${id}.${ts}.success

        elif [ "${load_id_type}" == "postgresql" ]; then
          echo "[INFO] load postgresql ..." 
        else
          echo "[ERROR] UNSUPPORTED LOAD TYPE: $load_id_type" && exit 1
        fi
      fi
    done

elif [ "$dw_action" == "transform" ]; then
  echo "transforming..."
elif [ "$dw_action" == "compose" ]; then
  echo "composing..."
else
  echo "${help_message}" && exit 0
fi
