#!/bin/bash
#set -x

if [ ! -e "${HOME}/.my.cnf" ]; then
    echo "Please create a MySQL defaults file named \"${HOME}/.my.cnf\""
elif [ ! -z "${1}" -a ! -z "${2}" ]; then
    database="${1}"
    username="${2}"

    chbs_url="https://us-east1-vst-main-prod.cloudfunctions.net/vst_chbs"
    chbs_output=$(curl ${chbs_url} -s | egrep "^Plaintext|^MySQL")
    
    plaintext=$(echo "${chbs_output}" | egrep "^Plaintext" | awk '{print $NF}')
    mysql_ciphertext=$(echo "${chbs_output}" | egrep "^MySQL" | awk '{print $NF}')

    this_sql="GRANT SELECT ON \`${database}\`.* TO '${username}'@'35.235.240.0/255.255.240.0' IDENTIFIED BY PASSWORD '${mysql_ciphertext}';"
    #echo "${this_sql}"

    reveal_url="https://reveal.vitalsource.com/secret/create"

    reveal_message="Database Host: $(hostname | awk -F'.' '{print $1}')"
    reveal_message+="\nDatabase: ${database}"
    reveal_message+="\nUsername: ${username}"
    reveal_message+="\nPassword: ${plaintext}"

    echo -ne "Creating user \"${username}\" with SELECT grant to \"${database}.*\" ... "
    echo "${this_sql}" | mysql > /dev/null 2>&1

    if [ ${?} -eq 0 ]; then
        echo "SUCCESS"

        echo -ne "Creating reveal secret link ... "
        reveal_output=$(curl -X POST -H "Content-Type: application/x-www-form-urlencoded" ${reveal_url} -d "secret=$(echo -e "${reveal_message}")" -s 2> /dev/null | egrep 'id="secret-link" value' | awk -F'"' '{print $(NF-1)}')

        if [ ! -z "${reveal_output}" ]; then
            echo "SUCCESS"
            echo "    Secret Link: ${reveal_output}"
        else
            echo "FAILED"
        fi

    else
        echo "FAILED"
    fi

else
    echo "    Usage: ${0} <database> <username>"
fi

