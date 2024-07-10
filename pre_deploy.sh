#!/usr/bin/env bash

# This script checks the necessity of app deployment.
# It reads the version of existing app and compares it to the version published on github repository.
# If the versions are identical, the scipt does nothing.
# On the other hand, if the versions are not identical, it executes deploy.sh script which is designed to deploy any shiny app in packaged form.
# To use this script, first you need to update config.yml file.
# For further instructions read deploy.sh INSTRUCTION section.
# Have a nice day!

# Function to read and parse the config file
read_config_file() {
    config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        exit 1
    fi

    # Read the config file and set variables
    while IFS=':' read -r key value; do
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | tr -d '[:space:]')

        case "$key" in
            github_repo_url) repo_url="$value" ;;
            inst_dir) inst_dir="$value" ;;
            model_function) model_function="$value" ;;
            server_name) server_name="$value" ;;
            ssl_certificate_path) ssl_certificate_path="$value" ;;
            ssl_certificate_key_path) ssl_certificate_key_path="$value" ;;
        esac
    done < "$config_file"
}

# Read and parse the config file
config_file="config.yml"
read_config_file "$config_file"

# Read, extract and display values
echo "GitHub Repo URL: $repo_url"
url=${repo_url#*://}
url=${url#*@}
author=$(echo "$url" | cut -d'/' -f2)
repo_name=$(basename "$(dirname "$(dirname "$repo_url")")")
repo_name_lowercase=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]')
ref_name=$(echo "$repo_url" | sed -E 's#.*/tree/([^/]+).*#\1#')

# Function to fetch the version from DESCRIPTION file in the GitHub repository
get_github_version() {
    local repo_url="$1"
    local version
    version=$(curl -s "$repo_url" | awk -F': ' '/Version:/ { print $2 }')
    echo "$version"
}

# Function to compare versions
compare_versions() {
    local local_version="$1"
    local github_version="$2"

    if [[ "$local_version" != "$github_version" ]]; then
        echo "Versions differ: Local Version - $local_version, GitHub Version - $github_version"
        return 0  # Versions differ
    else
        echo "Versions are the same: $local_version"
        return 1  # Versions are identical
    fi
}

# Function to execute deploy.sh if versions differ
execute_deploy() {
    local should_deploy="$1"

    if [[ "$should_deploy" -eq 0 ]]; then
        echo "Executing deploy.sh script..."
        sudo bash deploy.sh
    else
        echo "No need to deploy. Versions are the same."
    fi
}

# Execution

github_description_url="https://raw.githubusercontent.com/$author/$repo_name/$ref_name/DESCRIPTION"
echo "Github DESCRIPTION URL: $github_description_url"

# Check if local version exists
if [[ ! -d "$repo_name" ]]; then
    echo "Local version not found. Deploying for the first time."
    execute_deploy 0 "$repo_url"
    exit 0
fi

# Fetching versions
local_version=$(awk -F': ' '/Version:/ { print $2 }' "$repo_name/DESCRIPTION")
github_version=$(get_github_version "$github_description_url")

# Comparing versions
compare_versions "$local_version" "$github_version"
should_deploy=$?

# Execute deploy.sh if versions differ
execute_deploy "$should_deploy"
