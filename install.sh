#!/bin/bash

# Create ${HOME}/bin if absent
if [ ! -d "${HOME}/bin" ]; then
    echo "Creating '${HOME}/bin'"
    mkdir -p "${HOME}/bin"
    chmod 700 "${HOME}/bin"
fi

# Copy any *db*.sh script into ${HOME}/bin
for component in *db*.sh no_api_access ; do
    install_component="no"

    if [ -e "${HOME}/bin/${component}" ]; then
        diff -q ${component} "${HOME}/bin/${component}" > /dev/null 2>&1

        if [ ${?} -ne 0 ]; then
            install_component="yes"
        fi

        # Don't write over 'no_api_access' customizations
        if [ "${component}" = "no_api_access" ]; then
            install_component="no"
        fi

    else
        install_component="yes"
    fi

    if [ "${install_component}" = "yes" ]; then
        echo "Installing ${component} to '${HOME}/bin'"
        cp "${component}" "${HOME}/bin" &&
        chmod 700 "${HOME}/bin/${component}" 
    fi

done

# Create symbolic links to enable db_ops.sh functionality
for basename_alias in $(egrep ")$" db_ops.sh | egrep -v '=' | awk '{print $1}' | sed -e 's|)$||g') ; do

    if [ ! -L "${HOME}/bin/${basename_alias}" ]; then
        echo "Creating symlink for ${basename_alias} in '${HOME}/bin'"
        ln -s "${HOME}/bin/db_ops.sh" "${HOME}/bin/${basename_alias}"
    fi

done

# Seed ${HOME}/.my.cnf if absent
# NOTE: This file is intentionally broken - user needs to fix it!
if [ ! -e "${HOME}/.my.cnf" ]; then
    echo "Creating a default ~/.my.cnf ... NOTE: it is not properly configured on purpose!"
    cp my.cnf "${HOME}/.my.cnf"
    chmod 600 "${HOME}/.my.cnf"
fi

