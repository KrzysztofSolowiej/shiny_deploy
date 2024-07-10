#!/usr/bin/env bash

# INSTRUCTION
# This script aims to deploy any shiny application in packaged form that has a github repository.
# The application can utilize renv as a package manager, but it is not necessary to deploy.
# To run the script, use the bash command and the name of the script itself. Two arguments are required to run:

# The first argument takes the URL of the repository on github,
# e.g. https://github.com/BioGenies/imputomics/tree/failing-server
# The branch name is required, so you can't use https://github.com/BioGenies/imputomics
# To deploy the application from the main branch, use https://github.com/BioGenies/imputomics/tree/main

# The second argument takes the name of the folder in the inst directory.
# This folder should contain the application files (app.R file, etc.).
# e.g. Imputomics

# There is also a third optional argument for installing models. It takes a name of a function which installs required model.
# e.g. install_CancerGramModel

# Example of the run command: bash deploy.sh https://github.com/BioGenies/imputomics/tree/failing-server Imputomics
# Example with the third optional argument: bash deploy.sh https://github.com/BioGenies/CancerGram/tree/master CancerGram install_CancerGramModel
# Check deploy_log.txt for any info on deployment process.
# Enjoy!
# END OF INSTRUCTION

# Log file to record the deployment process
LOG_FILE="deploy_log.txt"

# Function to log messages to the log file
log_message() {
    echo "$(date) - $1" | tee -a "$LOG_FILE"
}

# Function to check if a package is installed
is_package_installed() {
    dpkg -l "$1" &> /dev/null
}

# Function to install Java JDK
install_java_jdk() {
    if ! is_package_installed "openjdk-8-jdk"; then
        log_message "Installing Java JDK..."
        sudo apt-get update >> "$LOG_FILE" 2>&1 || { log_message "Failed to update packages"; exit 1; }
        sudo apt-get install -y ca-certificates curl gnupg >> "$LOG_FILE" 2>&1 || { log_message "Failed to install required packages"; exit 1; }
        install -m 0755 -d /etc/apt/keyrings >> "$LOG_FILE" 2>&1 || { log_message "Failed to create directory"; exit 1; }
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1 || { log_message "Failed to download GPG key"; exit 1; }
        sudo chmod a+r /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1 || { log_message "Failed to change permissions"; exit 1; }
        sudo apt-get install -y openjdk-8-jdk >> "$LOG_FILE" 2>&1 || { log_message "Failed to install Java JDK"; exit 1; }
        log_message "Java JDK installed successfully."
    else
        log_message "Java JDK is already installed. Skipping installation."
    fi
}

# Function to install and configure Docker
install_configure_docker() {
    if ! is_package_installed "docker-ce"; then
        log_message "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh >> "$LOG_FILE" 2>&1 || { log_message "Failed to download Docker installation script"; exit 1; }
        sudo sh get-docker.sh >> "$LOG_FILE" 2>&1 || { log_message "Failed to install Docker CE"; exit 1; }
        sudo apt-get install -y docker-compose >> "$LOG_FILE" 2>&1 || { log_message "Failed to install Docker Compose"; exit 1; }

        # Update docker.service file
        sudo sed -i 's|ExecStart=.*|ExecStart=/usr/bin/dockerd -H unix:// -D -H tcp://127.0.0.1:2375|' /lib/systemd/system/docker.service >> "$LOG_FILE" 2>&1 || { log_message "Failed to update Docker service file"; exit 1; }

        sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1 || { log_message "Failed to reload daemon"; exit 1; }
        sudo systemctl restart docker >> "$LOG_FILE" 2>&1 || { log_message "Failed to restart Docker"; exit 1; }

        log_message "Docker installed and configured successfully."
    else
        log_message "Docker is already installed. Skipping installation."
    fi
}

# Function to install git
check_install_git() {
    if ! command -v git &> /dev/null; then
        log_message "Git is not installed. Installing Git..."
        sudo apt install -y git
        log_message "Git installation completed."
    else
        log_message "Git is already installed."
    fi
}

# Function to get the latest release version of Shinyproxy from GitHub
get_latest_release() {
    curl --silent "https://api.github.com/repos/openanalytics/shinyproxy/releases/latest" |
    grep '"tag_name":' |
    sed -E 's/.*"([^"]+)".*/\1/' |
    sed 's/^v//'
}

# Function to clone ShinyProxy repository, install Maven, and build ShinyProxy
clone_install_build_shinyproxy() {
    if [ ! -d "shinyproxy" ] || [ ! -e "shinyproxy/target/shinyproxy-$latest_release-exec.jar" ]; then
        log_message "Cloning ShinyProxy repository and installing Maven..."
        if [ ! -d "shinyproxy" ]; then
            sudo git clone https://github.com/openanalytics/shinyproxy.git >> "$LOG_FILE" 2>&1 || { log_message "Failed to clone ShinyProxy repository"; exit 1; }
        else
            log_message "ShinyProxy repository is already cloned. Skipping cloning."
        fi

        if [ ! -e "shinyproxy/target/shinyproxy-$latest_release-exec.jar" ]; then
            if ! command -v mvn &>/dev/null; then
                sudo apt-get install -y maven >> "$LOG_FILE" 2>&1 || { log_message "Failed to install Maven"; exit 1; }
                echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' | sudo tee -a ~/.bashrc > /dev/null
                source ~/.bashrc
            else
                log_message "Maven is already installed. Skipping installation."
            fi

            log_message "Building ShinyProxy..."
            cd shinyproxy || { log_message "Failed to access ShinyProxy directory"; exit 1; }
            sudo mvn -U clean install || { log_message "Failed to build ShinyProxy"; cd ..; exit 1; }
            cd ..
        else
            log_message "ShinyProxy is already built. Skipping build process."
        fi

        log_message "ShinyProxy cloned, Maven installed, and ShinyProxy built successfully."
    else
        log_message "ShinyProxy and Maven are already installed and built. Skipping installation and build."
    fi
}

# Function to copy the ShinyProxy JAR
copy_shinyproxy_jar() {
    if [ ! -e "shinyproxy-$latest_release-exec.jar" ]; then
        log_message "Copying ShinyProxy JAR file..."
        sudo cp "shinyproxy/target/shinyproxy-$latest_release-exec.jar" ./ >> "$LOG_FILE" 2>&1 || { log_message "Failed to copy ShinyProxy JAR file"; exit 1; }
        sudo chmod u+x shinyproxy-$latest_release-exec.jar
	log_message "ShinyProxy JAR file copied successfully."
    else
        log_message "ShinyProxy JAR file already exists in the root directory. Skipping copy operation."
    fi
}

# Extracting branch and repo name
repo_url=$1
url=${repo_url#*://}
url=${url#*@}
author=$(echo "$url" | cut -d'/' -f2)
repo_name=$(basename "$(dirname "$(dirname "$repo_url")")")
repo_name_lowercase=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]')
ref_name=$(echo "$repo_url" | sed -E 's#.*/tree/([^/]+).*#\1#')
model_function=${3:-NULL}
CURRENT_DIR="$PWD"
CURRENT_USER="$USER"

# Cloning/overwriting github repository
clone_repo_overwrite() {
    if [ -d "$repo_name" ]; then
        log_message "Removing existing $repo_name directory..."
        sudo rm -rf "$repo_name" >> "$LOG_FILE" 2>&1 || { log_message "Failed to remove $repo_name directory"; exit 1; }
    fi

    log_message "Cloning $repo_name repository..."
    if ! git clone -b "$ref_name" --single-branch "https://github.com/$author/$repo_name.git" "$repo_name" >> "$LOG_FILE" 2>&1; then
        log_message "Failed to clone $repo_name repository. Full git clone command: git clone -b $ref_name --single-branch https://github.com/$author/$repo_name.git $repo_name"
        exit 1
    fi
}

# Function to check if renv.lock exists in the cloned repository
check_renv_lock() {
    if [ -f "$repo_name/renv.lock" ]; then
        log_message "renv.lock found in the cloned repository."
        return 0
    else
        log_message "renv.lock not found in the cloned repository."
        return 1
    fi
}

# Function to install jq
check_install_jq() {
    if ! command -v jq &>/dev/null; then
        log_message "Installing jq..."
        sudo apt-get install -y jq >> "$LOG_FILE" 2>&1 || { log_message "Failed to install jq"; exit 1; }
        log_message "jq installed successfully."
    else
        log_message "jq is already installed. Skipping installation."
    fi
}

# Function to install nginx
check_install_nginx() {
    if ! command -v nginx &>/dev/null; then
        log_message "Installing nginx..."
        sudo apt-get install -y nginx >> "$LOG_FILE" 2>&1 || { log_message "Failed to install nginx"; exit 1; }
        log_message "nginx installed successfully."
    else
        log_message "nginx is already installed. Skipping installation."
    fi
}

# Function to check if renv.lock contains rJava package
check_rJava_in_renv_lock() {
    # Check if jq is installed
    check_install_jq

    # Use jq to parse renv.lock and check for rJava package
    if jq -e '.Packages | has("rJava")' "$repo_name/renv.lock" >/dev/null; then
        log_message "rJava package found in renv.lock."
        return 0
    else
        log_message "rJava package not found in renv.lock."
        return 1
    fi
}

# Function to check if DESCRIPTION file contains rJava package
check_rJava_in_DESCRIPTION() {
    if grep -Eq '^\s*(rJava|XLConnect)\s*,' "$repo_name/DESCRIPTION" || grep -Eq '^\s*(rJava|XLConnect)\s*$' "$repo_name/DESCRIPTION"; then
        log_message "rJava or XLConnect package found in DESCRIPTION file."
        return 0
    else
        return 1
    fi
}

# Function to check if README file mentions hmmer
check_hmmer_in_README() {
    if grep -q 'hmmer' "$repo_name/README.Rmd"; then
        log_message "hmmer found in README.Rmd file."
        return 0
    else
        return 1
    fi
}

# Function to check if DESCRIPTION file contains seqR package
check_seqR_in_DESCRIPTION() {
    if grep -q '^\s*seqR\s*,' "$repo_name/DESCRIPTION" || grep -q '^\s*seqR\s*$' "$repo_name/DESCRIPTION"; then
        log_message "seqR package found in DESCRIPTION file."
        return 0
    else
        return 1
    fi
}

# Function to determine non-CRAN packages
get_non_cran_packages() {
    if Rscript -e "if ('$repo_name' %in% rownames(available.packages())) { quit(status = 0) } else { quit(status = 1) }"; then
        echo "Package '$repo_name' is available on CRAN"
    else
        echo "Package '$repo_name' is not available on CRAN"
        # Get the path of the DESCRIPTION file
        description_file="$repo_name/DESCRIPTION"
        echo "$description_file"

        # Extract and format lines following "Imports:" from the DESCRIPTION file
        packages=$(awk '/^Imports:/ {flag=1; next} flag && /^    /{gsub(/\([^)]*\)/, ""); print substr($0, 5)} /^    / && $NF == "" {exit}' "$description_file" | awk '{$1=$1};1' | tr -d ',')

        # Array to store non-CRAN package names
        non_cran_packages=()

        # Loop over each package to check its availability on CRAN
        for package in $packages
        do
            if ! Rscript -e "if ('$package' %in% rownames(available.packages())) { quit(status = 0) } else { quit(status = 1) }"; then
                echo "Package '$package' is not available on CRAN"
                echo "Checking package availability..."
                non_cran_packages+=("$package")
            fi
        done

        # List of standard R libraries to filter out
        standard_packages=("stats" "graphics" "grDevices" "utils" "datasets" "methods" "tools" "base")

        # Remove standard R libraries from non-CRAN package list
        filtered_packages=()
        for package in "${non_cran_packages[@]}"
        do
            if [[ ! " ${standard_packages[@]} " =~ " ${package} " ]]; then
                filtered_packages+=("$package")
            fi
        done

        # Print non-CRAN package names without standard R libraries
        log_message "Non-CRAN Packages: ${filtered_packages[@]}"
    fi
}



# Function to check and install R packages
check_and_install_packages() {
    # Check if the package installation failed
    docker build -t "$repo_name_lowercase-img" . 2>&1 | tee build_log.txt

    if grep -q "Error installing package" build_log.txt; then
        log_message "Updating Dockerfile with package installations…"

        # Get the package names that failed to install
        failed_packages=$(grep -oP "Error installing package '\K[^']+" build_log.txt)

        while read -r failed_package; do
            # Extract package info from renv.lock using jq
            package_info=$(jq --arg pkg "$failed_package" '.Packages | with_entries(select(.key == $pkg))' $repo_name/renv.lock)
            package_repo=$(echo "$package_info" | jq -r '.[].RemoteRepo')
            package_ref=$(echo "$package_info" | jq -r '.[].RemoteRef')
            package_user=$(echo "$package_info" | jq -r '.[].RemoteUsername')

            log_message "Identified failed package: $failed_package"
            log_message "Package Repository: $package_repo"
            log_message "Package Branch/Ref: $package_ref"
            log_message "Package User Name: $package_user"

            # Check if any package info is null

            if [[ "$package_repo" != "null" && "$package_ref" != "null" && "$package_user" != "null" ]]; then
                # Create a temporary dockerfile with the necessary changes
                sed "/renv::restore()/ s|renv::restore()|devtools::install_github('$package_user/$package_repo', ref = '$package_ref'); renv::restore()|" dockerfile > dockerfile_tmp

                # Replace the original dockerfile with the updated content
                mv dockerfile_tmp dockerfile

                # Rebuild Docker image with the updated Dockerfile
                docker build -t "$repo_name_lowercase-img" .
            else
                log_message "Skipping package update in Dockerfile due to missing package information."
            fi

        done <<< "$failed_packages"
    else
        log_message "Docker image built successfully."
    fi
}

# Function to create Dockerfile based on renv.lock presence
create_dockerfile() {
    if [ -f "$repo_name/renv.lock" ]; then
        log_message "renv.lock found in the cloned repository. Using renv for package management."

        # Content of Dockerfile for renv.lock presence
        sudo cat > dockerfile <<EOL
FROM rocker/shiny-verse:$r_version

RUN apt-get update -qq && apt-get -y --no-install-recommends install \
    libxml2-dev \
    libcairo2-dev \
    libsqlite3-dev \
    libpq-dev \
    libssh2-1-dev \
    unixodbc-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libglpk-dev \
    libmagick++-dev \
    libgsl-dev

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean

RUN apt-get update
RUN apt-get install -y git
RUN apt install -y cmake
RUN apt install -y build-essential

COPY /$repo_name/inst/$inst_dir ./$repo_name
COPY /$repo_name/renv.lock ./

RUN ulimit -n 8192

RUN R -e "Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); install.packages('renv'); options(renv.consent = TRUE); install.packages(c('markdown', 'DT', 'shinyWidgets', 'shinythemes', 'shinycssloaders', 'colourpicker', 'shinyhelper', 'shinyalert', 'shinyEffects')); install.packages('devtools'); renv::restore(); devtools::install_github('$author/$repo_name', ref = '$ref_name', dependencies = TRUE)"

EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/$repo_name', host = '0.0.0.0', port = 3838)"]
EOL

    	if check_rJava_in_renv_lock; then
            log_message "Adding rJava setup to Dockerfile from renv.lock."
            sed -i '/RUN apt install -y build-essential/a \
            RUN apt install -y default-jre \
            RUN apt install -y default-jdk \
            RUN R CMD javareconf' dockerfile
    	fi

      #  get_non_cran_packages

      #  if [[ ${#filtered_packages[@]} -gt 0 ]]; then
          #  ulimit_line_number=$(grep -n "RUN ulimit -n 8192" dockerfile | cut -d ":" -f 1)
          #  new_line_number=$((ulimit_line_number + 1))
          #  packages_str=$(IFS=,; echo "${filtered_packages[*]}")
          #  new_line="RUN R -e \"Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); packages <- c('${packages_str}'); for(package in packages) BiocManager::install(package, update = TRUE)\""
          #  sed -i "${new_line_number}i ${new_line}" dockerfile
      #  fi

    else
        log_message "renv.lock not found in the cloned repository. App does not use renv for package management."
        # Content of Dockerfile for absence of renv.lock
        sudo cat > dockerfile <<EOL
FROM rocker/shiny-verse:latest

RUN apt-get update -qq && apt-get -y --no-install-recommends install \
    libxml2-dev \
    libcairo2-dev \
    libsqlite3-dev \
    libpq-dev \
    libssh2-1-dev \
    unixodbc-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libglpk-dev \
    libmagick++-dev \
    libgsl-dev

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean

RUN apt-get update
RUN apt-get install -y git
RUN apt install -y cmake
RUN apt install -y build-essential

COPY /$repo_name/inst/$inst_dir ./$repo_name

RUN ulimit -n 8192

RUN R -e "Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); install.packages(c('markdown', 'DT', 'shinyWidgets', 'shinythemes', 'shinycssloaders', 'colourpicker', 'shinyhelper', 'shinyalert', 'shinyEffects')); install.packages('$repo_name', dependencies = TRUE)"

EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/$repo_name', host = '0.0.0.0', port = 3838)"]
EOL
        get_non_cran_packages

	if Rscript -e "if ('$repo_name' %in% rownames(available.packages())) { quit(status = 0) } else { quit(status = 1) }"; then
	    echo "Package '$repo_name' is available on CRAN"
	else
	    echo "Package '$repo_name' is not available on CRAN"
	    sed -i "s|Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); install.packages(c('markdown', 'DT', 'shinyWidgets', 'shinythemes', 'shinycssloaders', 'colourpicker', 'shinyhelper', 'shinyalert', 'shinyEffects')); install.packages('$repo_name', dependencies = TRUE)|Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); install.packages(c('markdown', 'DT', 'shinyWidgets', 'shinythemes', 'shinycssloaders', 'colourpicker', 'shinyhelper', 'shinyalert', 'shinyEffects')); install.packages('devtools'); devtools::install_github('$author/$repo_name', ref = '$ref_name')|" dockerfile
	fi

        if [[ ${#filtered_packages[@]} -gt 0 ]]; then
            ulimit_line_number=$(grep -n "RUN ulimit -n 8192" dockerfile | cut -d ":" -f 1)
            new_line_number=$((ulimit_line_number + 1))
	    packages_str=""
	    for pkg in "${filtered_packages[@]}"; do
    	        packages_str+="'$pkg',"
	    done
	    packages_str=${packages_str%,}
	    new_line="RUN R -e \"Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); packages <- c(${packages_str}); for(package in packages) BiocManager::install(package, update = TRUE)\""
            sed -i "${new_line_number}i ${new_line}" dockerfile
        fi

        description_file="$repo_name/DESCRIPTION"
        packages=$(awk '/^Suggests:/ {flag=1; next} flag && /^    /{gsub(/\([^)]*\)|,$/, ""); printf "'\''%s'\'', ", $1} flag && $NF == "" {exit}' "$description_file")
        packages=$(echo "$packages" | sed 's/, $//')
        log_message "Suggested packages: $packages"

        # Check if packages variable has content
        if [[ ${#packages} -gt 0 ]]; then
            ulimit_line_number=$(grep -n "RUN ulimit -n 8192" dockerfile | cut -d ":" -f 1)
            new_line_number=$((ulimit_line_number + 1))
            new_line="RUN R -e \"Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); packages <- c($packages); for(package in packages) install.packages(package, dependencies = TRUE)\""
            sed -i "${new_line_number}i ${new_line}" dockerfile
        fi

        # Update dockerfile with non-CRAN package installation using BiocManager if needed
        if [[ ${#filtered_packages[@]} -gt 0 ]]; then
            if ! Rscript -e "if ('$repo_name' %in% rownames(available.packages())) { quit(status = 0) } else { quit(status = 1) }"; then
                # Replace the original line with devtools and BiocManager installation for non-CRAN packages
                sed -i "s|Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); install.packages(c('markdown', 'DT', 'shinyWidgets', 'shinythemes', 'shinycssloaders', 'colourpicker', 'shinyhelper', 'shinyalert', 'shinyEffects')); install.packages('$repo_name', dependencies = TRUE)|Sys.setenv(RENV_DOWNLOAD_METHOD = 'libcurl'); Sys.setenv('RENV_CONFIG_REPOS_OVERRIDE' = 'http://cran.rstudio.com'); install.packages(c('markdown', 'DT', 'shinyWidgets', 'shinythemes', 'shinycssloaders', 'colourpicker', 'shinyhelper', 'shinyalert', 'shinyEffects')); install.packages('devtools'); install.packages('BiocManager'); BiocManager::install('${filtered_packages[@]}'); devtools::install_github('$author/$repo_name', ref = '$ref_name')|" dockerfile
            fi
        fi

	# Update dockerfile if rJava package is present in DESCRIPTION file
    	if  check_rJava_in_DESCRIPTION; then
            log_message "Adding rJava setup to Dockerfile from DESCRIPTION file."
            sed -i '/RUN apt install -y build-essential/a \
            RUN apt install -y default-jre \
            RUN apt install -y default-jdk \
            RUN R CMD javareconf' dockerfile
    	fi

        # Update dockerfile if hmmer is found in README.Rmd file
        if check_hmmer_in_README; then
            log_message "Adding hmmer setup to Dockerfile from README.Rmd file."
            sed -i '/RUN apt install -y build-essential/a \
            RUN apt install -y hmmer' dockerfile
        fi

        # Update dockerfile if seqR is found in DESCRIPTION file
        if check_seqR_in_DESCRIPTION; then
            expose_line_number=$(grep -n "RUN ulimit -n 8192" dockerfile | cut -d ":" -f 1)
            new_line_number=$((expose_line_number - 1))
            new_line="RUN R -e \"if (!require('devtools')) install.packages('devtools'); devtools::install_github('slowikj/seqR')\""
            sed -i "${new_line_number}i ${new_line}" dockerfile
        fi

	# Update dockerfile if model_function is provided
	if [ "$model_function" != "NULL" ]; then
	    expose_line_number=$(grep -n "EXPOSE 3838" dockerfile | cut -d ":" -f 1)
	    new_line_number=$((expose_line_number - 1))
	    new_line="RUN R -e \"library($repo_name); $model_function()\""
	    sed -i "${new_line_number}i ${new_line}" dockerfile
	    log_message "Dockerfile updated with model installation command."
	fi
    fi
}

# Function to get IPv4
get_server_ipv4() {
    server_ipv4=$(curl -s https://ipinfo.io/ip)
    if [ $? -eq 0 ]; then
        echo "$server_ipv4"
    else
        server_ipv4=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

        if [ -n "$server_ipv4" ]; then
            echo "$server_ipv4"
        else
            log_message "Unable to retrieve IP using 'ip addr show'. Check network connectivity."
        fi
    fi
}

# Function to check if a port is in use
check_port() {
    local port=$1
    local process_info
    process_info=$(lsof -i -P -n | grep LISTEN | grep ":$port")
    if [[ -n $process_info ]]; then
        log_message "Port $port is in use by:"
        log_message "$process_info"
        log_message "Before starting the service, please release port $port."
        return 1
    else
        log_message "Port $port is available."
        return 0
    fi
}

# Function to check the status of my-shinyproxy service
check_my_shinyproxy_status() {
    if systemctl is-active --quiet my-shinyproxy; then
        log_message "my-shinyproxy service is active."
    else
        log_message "my-shinyproxy service is not active."
    fi
}

# Function to check the status of nginx service
check_nginx_status() {
    if systemctl is-active --quiet nginx; then
        log_message "nginx service is active."
    else
        log_message "nginx service is not active."
    fi
}

# Function to check if a Shiny application is running correctly
check_shiny_app_status() {
    app_url="$1"
    log_message "Wait 10 seconds..."
    sleep 10
    # Send a GET request to the Shiny app URL and capture the HTTP response code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "$app_url")

    if [ "$response_code" -eq 200 ]; then
        log_message "Deployment completed. The Shiny application is running correctly."
    else
        log_message "Deployment completed, but the Shiny application might be experiencing issues (HTTP status code: $response_code). Check deploy_log.txt"
    fi
}

#####################################
####### Execution starts here #######
#####################################

# Redirect all output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

log_message "Starting deployment..."

install_java_jdk
install_configure_docker
check_install_git

latest_release=$(get_latest_release)
log_message "ShinyProxy latest release: $latest_release"

clone_install_build_shinyproxy
copy_shinyproxy_jar

clone_repo_overwrite
check_renv_lock

# Extracting R version
check_install_jq

if check_renv_lock; then
    log_message "Using renv for package management."
    r_version=$(jq -r '.R.Version' "$repo_name/renv.lock")
else
    log_message "App does not use renv for package management."
fi

log_message "Author: $author"
log_message "Repo name: $repo_name"
log_message "Ref name: $ref_name"

if check_renv_lock; then
    log_message "R version: $r_version"
else
    log_message "R version: latest."
fi

log_message "inst dir: $2"
inst_dir=$2

# Create dockerfile
log_message "Creating dockerfile..."
create_dockerfile

if check_renv_lock; then
    log_message "Using renv for package management."
    check_and_install_packages
else
    log_message "App does not use renv for package management."
    docker build -t "$repo_name_lowercase-img" .
    log_message "Docker image built successfully."
fi

# Create application.yml
sudo cat > application.yml <<EOL
proxy:
  title: $repo_name
  hide-navbar: true
  heartbeat-rate: 10000
  heartbeat-timeout: 60000
  port: 4848
  container-wait-time: 50000
  authentication: none
  docker:
    url: http://localhost:2375
    port-range-start: 50000
  specs:
    - id: app
      port: 3838
      display-name: $repo_name
      container-cmd: ["R", "-e", "shiny::runApp('/$repo_name', host = '0.0.0.0', port = 3838)"]
      container-image: $repo_name_lowercase-img

logging:
  file:
    name: shinyproxy.log
EOL

# Create a service
sudo cat > /etc/systemd/system/my-shinyproxy.service <<EOL
[Unit]
Description=My ShinyProxy

[Service]
User=$CURRENT_USER
WorkingDirectory=$CURRENT_DIR
ExecStart=/usr/bin/java -jar $CURRENT_DIR/shinyproxy-$latest_release-exec.jar
Restart=always
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=my-shinyproxy

[Install]
WantedBy=multi-user.target
EOL

# Directing all traffic to shinyproxy
if [ -x "$(command -v apache2)" ]; then
    echo "Apache2 is installed."
    sudo systemctl stop apache2
    sudo systemctl disable apache2
    log_message "Apache2 stopped and disabled."
else
    log_message "Apache2 is not installed."
fi

check_install_nginx

server_ipv4=$(get_server_ipv4)
# Check if server_ipv4 is empty or invalid (optional check)
if [ -z "$server_ipv4" ]; then
    log_message "Failed to retrieve the server's IPv4 address."
    exit 1
fi

# Create or update nginx configuration
nginx_config="/etc/nginx/sites-enabled/default"

sudo bash -c "cat > $nginx_config" << 'EOL'
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name imputomics.umb.edu.pl;
    return 301 https://imputomics.umb.edu.pl$request_uri;
}

server {
    server_name imputomics.umb.edu.pl;
    listen 443 ssl;
    ssl_session_timeout  5m;
    ssl_protocols  SSLv2 SSLv3 TLSv1 TLSv1.2;
    ssl_ciphers  HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers   on;

    ssl_certificate         /home/cbk/certyfikat/imputomics_chained.cer;
    ssl_certificate_key     /home/cbk/certyfikat/imputomics_umb_edu_pl.key;

    access_log /var/log/nginx/imputomics.log;
    error_log /var/log/nginx/imputomics-error.log error;

    location / {
        proxy_set_header    Host $host;
        proxy_set_header    X-Real-IP $remote_addr;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        proxy_pass          http://localhost:4848/app_direct/app/;
        proxy_read_timeout  20d;
        proxy_buffering off;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_http_version 1.1;

        proxy_redirect      / $scheme://$host/;
    }
}
EOL

log_message "Nginx configuration updated with server's IP: $server_ipv4"

sudo systemctl reload nginx
sudo systemctl daemon-reload
sudo systemctl stop my-shinyproxy

# Check availability of port 4848 for ShinyProxy
if ! check_port 4848; then
    log_message "Port 4848 is not available. Unable to start my-shinyproxy service."
fi

sudo systemctl start my-shinyproxy
sudo systemctl enable my-shinyproxy

sudo systemctl stop nginx

# Check availability of port 80 for Nginx
if ! check_port 80; then
    log_message "Port 80 is not available. Unable to start nginx service."
fi

sudo systemctl start nginx
sudo systemctl enable nginx

check_my_shinyproxy_status
check_nginx_status

# Create monitor.sh file and add the monitoring script content
cat << 'EOF' > monitor.sh
#!/usr/bin/env bash

# Define the inactive duration threshold for containers (in minutes)
inactive_duration=60

# Check the number of running containers
container_count=$(docker ps -q | wc -l)

# Proceed only if there are running containers
if [[ $container_count -gt 0 ]]; then
    # Get a list of all containers with their activity status and ports
    containers=$(docker ps -a --format "{{.ID}}\t{{.Status}}\t{{.Names}}\t{{.Ports}}")

    # Iterate through each container and check the status, last activity time, and ports
    while IFS=$'\t' read -r container_id status name ports; do
        # Check if the container is in "Exited" status
        if [[ $status == "Exited" ]]; then
            # Remove the container
            docker rm $container_id
        else
            # Check if the container has no exposed ports
            if [[ -z $ports ]]; then
                # Stop and then remove the container without exposed ports
                docker stop $container_id
                docker rm $container_id
            else
                # Get the container's running time
                running_time=$(docker inspect --format="{{.State.StartedAt}}" $container_id)
                # Calculate the time difference in seconds
                if [[ -n $running_time ]]; then
                    running_time_seconds=$(date -d "$running_time" +%s)
                    current_time_seconds=$(date +%s)
                    active_time=$((current_time_seconds - running_time_seconds))
                    active_time_minutes=$((active_time / 60))

                    # Check if the container is active and running for more than the threshold
                    if [[ $active_time_minutes -gt $inactive_duration ]]; then
                        # Stop and then remove the inactive container
                        docker stop $container_id
                        docker rm $container_id
                    fi
                fi
            fi
        fi
    done <<< "$containers"
else
    echo "No running containers found."
fi

# Remove Docker images with <none> REPOSITORY
docker images | awk '/<none>/ { print $3 }' | xargs -r docker rmi -f

EOF

# Define the crontab command
CRON_COMMAND="*/10 * * * * $CURRENT_DIR/monitor.sh"
# CRON_COMMAND="*/10 * * * * echo 'password' | sudo -S bash $CURRENT_DIR/monitor.sh"

# Check if crontab exists for the root user
if crontab -u $CURRENT_USER -l &>/dev/null; then
    crontab -u $CURRENT_USER -r
fi

# Add the new command to the crontab
echo "$CRON_COMMAND" | crontab -u $CURRENT_USER -

log_message "Monitoring script created and scheduled with cron."
crontab -u $CURRENT_USER -l

# Check shiny app status
get_server_ipv4
check_shiny_app_status "$server_ipv4"
