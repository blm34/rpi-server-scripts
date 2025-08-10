#!/bin/bash

set -u
set -o pipefail

# Read variables in from the .env file
source ~/rpi-server-scripts/.env

if [[ -z "${GPG_KEY}" ]]; then
    echo "ERROR: GPG_KEY is not set. Check ~/rpi-server-scripts/.env"
    exit 1
fi

# Base Paths
usr_path="/home/${USER}"
containers_dir="${usr_path}/containers"
env_repo="${usr_path}/containers/rpi-server-docker-env-vars"

# Check env file repo exists. If not clone it
if [[ ! -d "${env_repo}" ]]; then
    echo "Repository 'rpi-server-docker-env-vars' not found. Cloning it instead."
    cd "${containers_dir}" || exit 1
    git clone --quiet git@github.com:blm34/rpi-server-docker-env-vars.git
fi

cd "${env_repo}" || exit 1

gpg_key_exists() {
    local key="$1"
    if gpg --list-keys --with-colons "${key}" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

updated_repos=""

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
        if gpg --batch --decrypt --quiet "${encrypted_file}" 2>/dev/null | cmp --quiet "${env_file}" -; then
            echo "    Skipping - no changes found"
            continue
        else
            # Check whether gpg failed or files differ
            gpg_status=${PIPESTATUS[0]}
            if [[ $gpg_status -ne 0 ]]; then
                echo "    WARNING: Decryption failed (gpg status ${gpg_status}). Will re-encrypt"
            else
                echo "    Changes found in .env file"
            fi
            rm "${encrypted_file}"
        fi
        echo "    New .env file found"
    fi

    # Check recipient key exists before trying to encrypt
    if ! gpg_key_exists "${GPG_KEY}"; then
        echo "    ERROR: GPG public key '${GPG_KEY}' not found in local keyring."
        continue
    fi

    # Encrypt the .env file
    if gpg --encrypt --quiet --recipient "${GPG_KEY}"  --output "${encrypted_file}" "${env_file}"; then
        echo "    Encrypted OK: ${encrypted_file}"
    else
        echo "    ERROR: encryption failed for ${env_file}. Skipping commit for ${container_name}."
    fi

    if [[ -f "${encrypted_file}" ]]; then
        # Commit the backup to git
        echo "    Commiting ${container_name}/.env.gpg"
        git add "${container_name}/.env.gpg"
        if git commit --quiet -m "Update encrypted .env file for ${container_name}"; then
            updated_repos+="${container_name}, "
        else
            echo "    Nothing to commit or commit failed for ${container_name}"
        fi
    else
        echo "    Unexpected: ${encrypted_file} missing after successful encrypt"
    fi
done

if [[ $(git rev-list --count origin/main..HEAD) -eq 0 ]]; then
    echo "No updates to .env files"
else
    echo "Pushing changes to github"
    git push --quiet origin main

	updated_repos=${updated_repos%, }
	curl --silent --output /dev/null -H "Title: Docker .env files updated" -d "The following repos have had their .env files updated: ${updated_repos}" ${NTFY_URL}/rpi_cron
fi

