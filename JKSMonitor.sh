#!/bin/bash

# Environment
readonly ENV="PROD"

declare -a keystore_paths
declare -a keystore_passes

# List of keystore_paths and corresponding keystore_passes (use the same index)
# keystore 1
keystore_paths[0]="/[keystore1_dir]/[keystore1_name]"
keystore_passes[0]="[keystore1_pass]"
# keystore 2
keystore_paths[1]="/[keystore2_dir]/[keystore2_name]"
keystore_passes[1]="[keystore2_pass]"

# A certificate expiring in THRESHOLD_DAYS days will result in a warning
readonly THRESHOLD_DAYS=7

# Comma separated list of emails
readonly  MAIL_TO="mailto1@host.com,mailto2@host.com"

# ----------- Do not make changes after this line -----------

current_date=$(date +%s)
declare -i threshold_sec
threshold_sec=$(( current_date + (THRESHOLD_DAYS * 24 * 60 * 60) ))

# Loop through all keystore_paths using index i
for i in "${!keystore_paths[@]}"; do
    
    # Check if the provided Java keystore exists:
    if [[ ! -s "${keystore_paths[i]}" ]]; then
        echo "[ERROR]    Java keystore '${keystore_paths[i]}' \
            was not found in '${ENV}'."
        # Go to the next keyStorePath in the array
        continue
    fi

    echo "============================"
    echo -e "Processing ${keystore_paths[i]}...\n"
    
    # Get all the data on the keystore from keytool
    keytool_list=$(keytool -list -v -keystore "${keystore_paths[i]}" \
        -storepass "${keystore_passes[i]}")
    
    # Create an array of lines containing alias names and get its length
    keytool_alias_list=$(echo "${keytool_list}" | grep "Alias name:")
    readarray -t keytool_alias_lines <<< "${keytool_alias_list}"
    declare -i keytool_alias_lines_cnt
    keytool_alias_lines_cnt=${#keytool_alias_lines[@]}
    
    # Create an array of lines containing validation dates and get its length
    keytool_validity_dt_list=$(echo "${keytool_list}" | grep "Valid from:")
    readarray -t keytool_validity_dt_lines <<< "${keytool_validity_dt_list}"
    declare -i keytool_validity_dt_lines_cnt
    keytool_validity_dt_lines_cnt=${#keytool_validity_dt_lines[@]}

    # Create an key-value array of alias names and their valid until dates
    declare -A alias_validity_list
    if (( keytool_alias_lines_cnt == keytool_validity_dt_lines_cnt ))
    then
        # The easy way
        for (( index=0; index<keytool_alias_lines_cnt; index++ )); do
            alias_name="${keytool_alias_lines[index]##*Alias name: }"
            valid_until="${keytool_validity_dt_lines[index]##*until: }"
            alias_validity_list+=([${alias_name}]=${valid_until})
        done
    else
        # The hard way (and a very long one, too)
        for keytool_alias_line in "${keytool_alias_lines[@]}"; do
            alias_name="${keytool_alias_line##*Alias name: }"
            validityDatesLine="$(keytool -list -v -keystore "${keystore_paths[i]}" \
                -storepass "${keystore_passes[i]}" -alias "${alias_name}" \
                | grep "Valid from" \
                | head -1)"
            valid_until="${validityDatesLine##*until: }"
            alias_validity_list+=([${alias_name}]=${valid_until})
        done
    fi

    # Check if alias has expired ==> certificates_expired, \
        or is about to expire ==> certificates_expiring
    declare -a certificates_expired
    declare -a certificates_expiring
    declare -i until_sec
    for alias_name in "${!alias_validity_list[@]}"; do
        valid_until="${alias_validity_list[${alias_name}]}"
        until_sec=$(date -d "${valid_until}" +%s)
        days_remaining=$(( (until_sec - $(date +%s))/60/60/24 ))
        if (( days_remaining <= 0 )); then
            certificates_expired+=("[CRITICAL] '${alias_name}' expired on '${valid_until}'")
        elif (( threshold_sec >= until_sec )); then
            certificates_expiring+=("[WARNING]  '${alias_name}' expires on '${valid_until}'. \
                Days until expiration: ${days_remaining}\n")
        fi
    done

    declare -i alias_validity_list_cnt
    alias_validity_list_cnt=${#alias_validity_list[@]}
    declare -i certificates_expired_cnt
    certificates_expired_cnt=${#certificates_expired[@]}
    declare -i certificates_expiring_cnt
    certificates_expiring_cnt=${#certificates_expiring[@]}

    keystore_name="${keystore_paths[i]##*/}"
    if (( certificates_expired_cnt > 0 || certificates_expiring_cnt > 0 )); then
        if (( certificates_expired_cnt > 0 && certificates_expiring_cnt > 0 )); then
            warning_msg="Warning! Both expiring and expired certificates were detected in \
                '${keystore_paths[$1]}' in '${ENV}'.\n"
            mail_subject="[WARNING] Update certificates in '${keystore_name}' in '${ENV}'. \
                Expired: ${certificates_expired_cnt}. \
                About to expire: ${certificates_expiring_cnt}"
            echo -e "${warning_msg}"
            list_critical=$(for crt in "${certificates_expired[@]}"; do echo "${crt}"; done | sort)
            echo -e "${list_critical}"
            list_warnings=$(for crt in "${certificates_expiring[@]}"; do echo "${crt}"; done | sort)
            echo -e "${list_warnings}"
            mail_body="${warning_msg}\n${list_warnings}\n${list_critical}\n"
        
        elif (( certificates_expired_cnt > 0 && certificates_expiring_cnt == 0 )); then
            warning_msg="Warning! Expired certificates were detected in ${keystore_paths[$1]} in ${ENV}.\n"
            mail_subject="[WARNING] Update certificates in ${keystore_name} (${ENV}). \
                Expired: ${certificates_expired_cnt}."
            echo -e "${warning_msg}"
            list_critical=$(for crt in "${certificates_expired[@]}"; do echo "${crt}"; done | sort)
            echo -e "${list_critical}"
            mail_body="${warning_msg}\n${list_critical}\n"
        
        else
            warning_msg="Warning! Expiring certificates were detected in '${keystore_paths[$1]}' in ${ENV}.\n"
            mail_subject="[WARNING] Update certificates in '${keystore_name}' in '${ENV}'. \
                About to expire: ${certificates_expiring_cnt}"
            echo -e "${warning_msg}"
            list_warnings=$(for crt in "${certificates_expiring[@]}"; do echo "${crt}"; done | sort)
            echo -e "${list_warnings}"
            mail_body="${warning_msg}\n${list_warnings}\n"
        fi
        
        # Send notification by email
        echo -e "${mail_body}" | mail -s "${mail_subject}" "$MAIL_TO"

    elif (( alias_validity_list_cnt == 0 )); then
        echo "No certificates were found in '${keystore_name}'."
    
    else
        echo "All certificates in '${keystore_name}' are valid."
    fi
    
    echo -e "\n"

    unset alias_validity_list
    unset certificates_expired
    unset certificates_expiring

done