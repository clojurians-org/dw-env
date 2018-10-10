bash dw.sh extract ERP-1.0.0 --input /app/edwhr/dw-data/data_in/ERP --max-num 3 --max-bytes 1G
bash dw.sh load:merge TestA-1.0.0:oracle --extract-id ERP-1.0.0 --connect-id 'TEST_ENV_STA_TNS,TEST_ENV_ODS_TNS' --input 'ERP-*/TestA-*.dat' --format ",|:a,b,c"
bash dw.sh load:merge TestA-1.0.0:oracle --extract-id ERP-1.0.0 --connect-id 'TEST_ENV_STA_TNS,TEST_ENV_ODS_TNS' --input 'ERP-*/TestA-*.dat' --format @/app/edwhr/dw-data/control/T_ERP_T_BILLLADING_TR.ctl
bash dw.sh load:merge TestA-1.0.0:postgresql --extract-id ERP-1.0.0 --input 'ERP-*/TestA-*.dat' --format ",|:a,b,c"


bash dw.sh compose ERP-1.0.0 TestA-1.0.0:oracle TestB-1.0.0:oracle
