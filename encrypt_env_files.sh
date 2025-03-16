#!/bin/bash

# Read variables in from the .env file
source ~/rpi-server-scripts/.env

# Base Paths
usr_path="/home/${USER}"
containers_dir="${usr_path}/containers"
env_repo="${usr_path}/containers/rpi-server-docker-env-vars"

# Check env file repo exists. If not clone it
if [[ ! -d "${env_repo}" ]]; then
    echo "Repository 'rpi-server-docker-env-vars' not found. Cloning it instead."
    cd "${containers_dir}"
    git clone --quiet git@github.com:blm34/rpi-server-docker-env-vars.git
fi

cd "${env_repo}"

# Loop through containers
for container_path in "${containers_dir}"/*/; do
    full_container_name=$(basename "${container_path}")
    echo "Checking ${full_container_name}"

    # Check the directory is a docker container repository
    if [[ ! "${full_container_name}" == rpi-server-* ]]; then
        echo "    Skipping - not a source controlled docker repo"
	continue
    fi

    container_name=${full_container_name#rpi-server-}

    env_file="${container_path}.env"
    encrypted_file="${env_repo}/${container_name}/.env.gpg"

    # Validate .env file exists
    if [[ ! -f "${env_file}" ]]; then
        echo "    Skipping - no .env file found"
	continue
    fi

    # Create the target directory if it doesn't exist
    mkdir -p "${env_repo}/${container_name}"

    # Check if there is an identical, existing encrypted file
    if [[ -f "${encrypted_file}" ]]; then
	echo "    Existing .env found - checking for changes"
        mkdir "${env_repo}/tmp"
	decrypted_file="${env_repo}/tmp/.env" 
	gpg --decrypt --quiet --recipient "${gpg_key}" --output "${decrypted_file}" "${encrypted_file}"
	if cmp --quiet "${env_file}" "${decrypted_file}"; then
            echo "    Skipping - no changes found"
	    rm -r "${env_repo}/tmp"
	    continue
	else
	    echo "    Changes found in .env file"
	    rm ${encrypted_file}
	    rm -r "${env_repo}/tmp"
	fi
    else
	echo "    New .env file found"
    fi

    # Encrypt the .env file
    gpg --encrypt --quiet --recipient "${gpg_key}"  --output "${encrypted_file}" "${env_file}"

    # Commit the backup to git
    echo "    Commiting ${container_name}/.env.gpg"
    git add "${container_name}/.env.gpg"
    git commit --quiet -m "Update encrypted .env file for ${container_name}"
done

if [[ $(git rev-list --count origin/main..HEAD) -eq 0 ]]; then
    echo "No updates to .env files"
else
    echo "Pushing changes to github"
    git push --quiet origin main
fi

