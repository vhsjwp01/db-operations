#!/bin/bash
#set -x

db_types="dbm dbv gdbm"
dir_name=$(dirname "${0}")
no_api_access_file="${dir_name}/no_api_access"

if [ ! -z "${VRSE_PATH}" -a -e "${no_api_access_file}" ]; then
    echo "Building no api access file per project ... please be patient"
    all_projects=$(gcloud projects list 2> /dev/null | awk '{print $1}' | egrep -i '^vst-' | sort -u)
    
    # Build no API access list
    for project in ${all_projects} ; do
        let no_instance_api=$(echo "N" | gcloud --project=${project} compute instances list 2>&1 | egrep -c "API \[compute.googleapis.com\] not enabled on project|is not found and cannot be used for API calls")

        if [ ${no_instance_api} -gt 0 ]; then
            let dbm_identified=$(egrep -c "dbm:${project}" "${no_api_access_file}")
            let dbv_identified=$(egrep -c "dbv:${project}" "${no_api_access_file}")

            if [ ${dbm_identified} -eq 0 ]; then
                echo "dbm:${project}" >> "${no_api_access_file}"
            fi

            if [ ${dbv_identified} -eq 0 ]; then
                echo "dbv:${project}" >> "${no_api_access_file}"
            fi

        fi

    done

    # Identify all possible DB hosts in each project
    for project in ${all_projects} ; do
    
        for db_type in ${db_types} ; do
            output_file="${db_type}.$(date +%Y%m%d)"

            case ${db_type} in

                dbm)

                    if [ -e "${no_api_access_file}" ]; then
                        let no_api_access=$(egrep -c "^${db_type}:${project}$" "${no_api_access_file}")
                    fi

                    if [ ${no_api_access} -eq 0 ]; then
                        echo "Identifying MySQL compute instances in project ${project}" >&2

                        for instance in $(gcloud --project=${project} compute instances list | egrep '\-db\-|\-dbm\-' | egrep -v '\-proxy\-' | egrep -i "running" | awk '{print $1}' | sort -u) ; do
                            echo "${instance}"
                        done >> "${output_file}"

                    fi

                ;;

                dbv)

                    if [ -e "${no_api_access_file}" ]; then
                        let no_api_access=$(egrep -c "^${db_type}:${project}$" "${no_api_access_file}")
                    fi

                    if [ ${no_api_access} -eq 0 ]; then
                        echo "Identifying Vertica compute instances in project ${project}" >&2

                        for instance in $(gcloud --project=${project} compute instances list | egrep '\-dbv\-' | egrep -v '\-proxy\-' | egrep -i "running" | awk '{print $1}' | sort -u) ; do
                            echo "${instance}"
                        done >> "${output_file}"

                    fi

                ;;


                gdbm)
                    echo "Identifying CloudSQL instances in project ${project}" >&2

                    for instance in $(gcloud --project=${project} sql instances list | awk '{print $1}' | egrep -v "^NAME" | sort -u) ; do
                        echo "${instance}"
                    done >> "${output_file}"

                ;;
    
            esac

        done

    done

else
    echo "Please export your path to VRSE as 'VRSE_PATH'"
    echo "Please make sure the file '${no_api_access_file}' exists"
fi

