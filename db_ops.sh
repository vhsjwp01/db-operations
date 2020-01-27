#!/bin/bash 
#set -x

my_basename=$(basename "${0}")
my_dirname=$(dirname "${0}")

user_list="${1}"

if [ ! -z "${user_list}" ]; then
    user_list=$(echo "${user_list}" | sed -e 's|:| |g' -e 's|,| |g' -e 's?|? ?g')

    case ${my_basename} in

        show_users)
            echo "use mysql ; select user,host from user ;" | mysql | awk '{print $1 ":" $2}' | egrep -v "^:$" | egrep -iv "^user:host$"
        ;;

        find_users)

            for user in ${user_list} ; do
                echo "use mysql ; select user,host from user ;" | mysql | awk '{print $1 ":" $2}' | egrep "${user}" | egrep -v "^:$"
            done

        ;;

        show_grants)

            for user in ${user_list} ; do

                for user_entry in $("${my_dirname}/find_users" ${user}) ; do
                    this_user=$(echo "${user_entry}" | awk -F':' '{print $1}')
                    this_host=$(echo "${user_entry}" | awk -F':' '{print $2}')

                    if [ "${this_host}" = "%" ]; then
                        echo "use mysql ; show grants for ${this_user} ;" | mysql | sed -e 's|IDENTIFIED BY PASSWORD.*$||g'
                    else
                        echo "use mysql ; show grants for '${this_user}'@'${this_host}' ;" | mysql | sed -e 's|IDENTIFIED BY PASSWORD.*$||g'
                    fi

                    echo
                done

            done

        ;;

        drop_users)

            for user in ${user_list} ; do

                for user_entry in $("${my_dirname}/find_users" ${user}) ; do
                    this_user=$(echo "${user_entry}" | awk -F':' '{print $1}')
                    this_host=$(echo "${user_entry}" | awk -F':' '{print $2}')

                    echo "use mysql ; drop user '${this_user}'@'${this_host}' ;" | mysql
                done

            done

        ;;

    esac

fi

