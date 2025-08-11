#!/bin/bash

set -u

container=${1}

# Base Paths
usr_path="/home/ben"
containers_dir="${usr_path}/containers"
container_dir="${containers_dir}/rpi-server-${container}"
env_repo="${containers_dir}/rpi-server-docker-env-vars"

# Check container directory exists
if [[ ! -d "${container_dir}" ]]; then
    echo "No directory found for container '${container}'"
    exit 1
fi

# Check env file repo exists. If not clone it
if [[ ! -d "${env_repo}" ]]; then
    echo "Repository 'rpi-server-docker-env-vars' not found. Cloning it instead."
    cd "${containers_dir}"
    git clone --quiet git@github.com:blm34/rpi-server-docker-env-vars.git
fi

cd "${container_dir}"
encrypted_file="${env_repo}/${container}/.env.gpg"
decrypted_file="${container_dir}/.env"

# Check if the encrypted file exists
if [[ ! -f "${encrypted_file}" ]]; then
    echo "No encrypted file in rpi-server-docker-env-vars repository for this container"
    exit 1
fi

# Decrypt the file
gpg --decrypt --quiet --output "${decrypted_file}" "${encrypted_file}"

echo "Successfully decrypted .env file for ${container}"

