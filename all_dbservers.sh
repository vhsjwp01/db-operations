#!/bin/bash
#set -x

db_types="dbm dbv gdbm"
dir_name=$(dirname "${0}")
no_api_access_file="${dir_name}/no_api_access"

if [ ! -z "${VRSE_PATH}" ]; then
    
    for project in $(gcloud projects list 2> /dev/null | awk '{print $1}' | egrep -i '^vst-' | sort -u) ; do
        let no_api_access=0

        # If you create a ${HOME}/bin/no_api_access file and place GCP project names in it
        # then this script will check it to make sure we don't hit a project that does not have
        # API access turned on, otherwise we'll assume API access is working
        if [ -e "${no_api_access_file}" ]; then
            let no_api_access=$(egrep -c "^${project}$" "${no_api_access_file}")
        fi
    
        if [ ${no_api_access} -eq 0 ]; then

            for db_type in ${db_types} ; do
                output_file="${db_type}.$(date +%Y%m%d)"

                case ${db_type} in

                    dbm)
                        echo "MySQL compute instances in project ${project}" >&2

                        for instance in $(gcloud --project=${project} compute instances list | egrep '\-db\-|\-dbm\-' | egrep -i "running" | awk '{print $1}' | sort -u | egrep -v '\-proxy\-') ; do
                            echo "${instance}"
                        done >> "${output_file}"

                    ;;

                    dbv)
                        echo "Vertica compute instances in project ${project}" >&2

                        for instance in $(gcloud --project=${project} compute instances list | egrep '\-dbv\-' | egrep -i "running" | awk '{print $1}' | sort -u) ; do
                            echo "${instance}"
                        done >> "${output_file}"

                    ;;


                    gdbm)
                        echo "CloudSQL instances in project ${project}" >&2

                        for instance in $(gcloud --project=${project} sql instances list | awk '{print $1}' | egrep -v "^NAME" | sort -u) ; do
                            echo "${instance}"
                        done >> "${output_file}"

                    ;;
    
                esac

            done

        fi

    done

fi
