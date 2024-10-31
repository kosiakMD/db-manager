#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

##########################
# Configuration Variables
##########################

# Default configurations
DEFAULT_DB_USER="dummy"
DEFAULT_DB_PASSWORD="dummy"
DEFAULT_POSTGRES_VERSION="15.8"  # Adjust based on your dump version
BASE_CONTAINER_NAME="dummy-local"
BASE_DB_NAME="dummy-local"
BASE_HOST_PORT=5432  # Default port
DEFAULT_DUMP_TYPE="postgresql"
DEFAULT_DUMP_PATH="./test-db.sql"  # Default path to the SQL dump file

# Directory to store SQL dumps inside the container
CONTAINER_DUMP_DIR="/tmp"

# Color Definitions
ERROR=$(tput setaf 1) # Red
SUCCESS=$(tput setaf 10) # Light Green
RED_LIGHT=$(tput setaf 9) # Red Light
GREEN=$(tput setaf 2) # Green
WARNING=$(tput setaf 3) # Yellow
GREY_LIGHT=$(tput setaf 7)
INFO_RISKY=$(tput setaf 11)
BLUE=$(tput setaf 4)
BLUE_LIGHT=$(tput setaf 14)
TEAL=$(tput setaf 6)
PURPLE=$(tput setaf 5)
PURPLE_LIGHT=$(tput setaf 13)
BLUE_DEEP=$(tput setaf 12)
NC=$(tput sgr0) # No Color

##########################
# Helper Functions
##########################

# Function to display usage information
usage() {
    echo "Usage: $0 {create|start|stop|remove|list|menu}"
    echo
    echo "Commands:"
    echo "  create  - Create a new PostgreSQL container for a feature."
    echo "  start   - Start an existing PostgreSQL container."
    echo "  stop    - Stop a running PostgreSQL container."
    echo "  remove  - Remove a PostgreSQL container."
    echo "  list    - List all managed PostgreSQL containers."
    echo "  menu    - Launch interactive menu."
    echo
    echo "Options for 'create' command:"
    echo "  -n    Feature name (required for create). Example: feature-login"
    echo "  -f    Path to the .sql dump file (optional; default: $DEFAULT_DUMP_PATH)"
    echo "  -p    Host port for PostgreSQL (optional; default: $BASE_HOST_PORT)"
    echo "  -d    Database name suffix (optional; default: none)"
    echo "  -u    Database user (optional; default: $DEFAULT_DB_USER)"
    echo "  -w    Database password (optional; default: $DEFAULT_DB_PASSWORD)"
    echo
    echo "Example Usages:"
    echo "  $0 create -n feature-login -f /path/to/dump.sql"
    echo "  $0 create -n feature-payment  # Uses default dump file"
    echo "  $0 start -n feature-login"
    echo "  $0 stop -n feature-login"
    echo "  $0 remove -n feature-login"
    echo "  $0 list"
    echo "  $0 menu"
    exit 1
}

# Function to check if a Docker container exists
container_exists() {
    local name="$1"
    docker ps -a --filter "name=^/${name}$" --format "{{.Names}}" | grep -w "$name" > /dev/null 2>&1
}

# Function to check if a Docker container is running
container_running() {
    local name="$1"
    docker ps --filter "name=^/${name}$" --filter "status=running" --format "{{.Names}}" | grep -w "$name" > /dev/null 2>&1
}

# Function to check if a port is available
is_port_available() {
    local port="$1"
    ! lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null
}

# Function to sanitize feature name for use in Docker names
sanitize_feature_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_' | sed 's/_*$//'
}

# Function to detect dump type
detect_dump_type() {
    local sql_file="$1"
    local head_lines
    head_lines=$(head -n 10 "$sql_file")

    if echo "$head_lines" | grep -q "^-- PostgreSQL database dump"; then
        echo "postgresql"
    else
        echo "unsupported"
    fi
}

# Function to create a new PostgreSQL container
create_container() {
    local feature_name="$1"
    local dump_file="$2"
    local host_port="$3"
    local db_suffix="$4"
    local db_user="$5"
    local db_password="$6"

    # Sanitize feature name
    local sanitized_feature_name
    sanitized_feature_name=$(sanitize_feature_name "$feature_name")
    echo -e "${BLUE_LIGHT}Sanitized feature name:${NC} $sanitized_feature_name"

    # Define container name and db_name based on db_suffix
    local container_name
    local db_name

    if [[ -z "$db_suffix" ]]; then
        container_name="${BASE_CONTAINER_NAME}_${sanitized_feature_name}"
        db_name="$BASE_DB_NAME"
    else
        container_name="${BASE_CONTAINER_NAME}_${sanitized_feature_name}"
        db_name="${BASE_DB_NAME}_${db_suffix}"
    fi
    echo -e "${BLUE_LIGHT}Container name:${NC} $container_name"

    # Check if container already exists
    if container_exists "$container_name"; then
        echo -e "${ERROR}Error:${NC} Container '$container_name' already exists."
        exit 1
    fi

    # Detect dump type
    local dump_type
    dump_type=$(detect_dump_type "$dump_file")
    if [[ "$dump_type" != "$DEFAULT_DUMP_TYPE" ]]; then
        echo -e "${ERROR}Error:${NC} Unsupported dump type. Only PostgreSQL dumps are supported."
        exit 1
    fi

    # Port assignment logic
    if [[ -n "$host_port" ]]; then
        if is_port_available "$host_port"; then
            echo -e "${BLUE_LIGHT}Using specified host port:${NC} $host_port"
        else
            echo -e "${ERROR}Error:${NC} Port $host_port is already in use. Please specify a different port using the -p option."
            exit 1
        fi
    else
        # Attempt to use default port 5432
        if is_port_available "$BASE_HOST_PORT"; then
            host_port="$BASE_HOST_PORT"
            echo -e "${SUCCESS}Assigned default host port:${NC} $host_port"
        else
            echo -e "${ERROR}Error:${NC} Default port $BASE_HOST_PORT is already in use."
            echo -e "Please specify a different port using the -p option."
            exit 1
        fi
    fi

    echo -e "${INFO_RISKY}Creating PostgreSQL container '$container_name' with DB '$db_name' on port $host_port...${NC}"

    # Start PostgreSQL container
    docker run --name "$container_name" \
        -e POSTGRES_DB="$db_name" \
        -e POSTGRES_USER="$db_user" \
        -e POSTGRES_PASSWORD="$db_password" \
        -p "${host_port}":5432 \
        -d postgres:"$DEFAULT_POSTGRES_VERSION"

    # Function to clean up the Docker container on failure
    cleanup_on_failure() {
        echo -e "${WARNING}An error occurred. Cleaning up...${NC}"
        docker stop "$container_name" > /dev/null 2>&1 || true
        docker rm "$container_name" > /dev/null 2>&1 || true
    }

    trap cleanup_on_failure ERR

    # Wait for PostgreSQL to be ready
    echo -e "${GREY_LIGHT}Waiting for PostgreSQL to be ready...${NC}"
    until docker exec "$container_name" pg_isready -U "$db_user" -d "$db_name" > /dev/null 2>&1; do
        echo -n "."
        sleep 2
    done
    echo
    echo -e "${SUCCESS}PostgreSQL is ready.${NC}"

    # Copy the SQL dump into the container
    docker cp "$dump_file" "$container_name":"$CONTAINER_DUMP_DIR/dump.sql"

    # Execute the SQL dump
    echo -e "${INFO_RISKY}Restoring the database from '$dump_file'...${NC}"
    docker exec -e PGPASSWORD="$db_password" "$container_name" psql -U "$db_user" -d "$db_name" -f "$CONTAINER_DUMP_DIR/dump.sql"

    # Update 'database' column in 'metadata' table
    echo -e "${INFO_RISKY}Updating 'database' column in 'metadata' table to '$db_name' where applicable...${NC}"
    # rewrite NOT NULL 'database' column in 'metadata' table
    docker exec -e PGPASSWORD="$db_password" "$container_name" psql -U "$db_user" -d "$db_name" -c "UPDATE public.metadata SET database = '$db_name' WHERE database IS NOT NULL;"

    echo -e "${SUCCESS}Database restoration completed successfully.${NC}"

    # Remove the SQL dump from the container
    docker exec "$container_name" rm "$CONTAINER_DUMP_DIR/dump.sql"

    # Remove the trap
    trap - ERR

    echo -e "${BLUE_LIGHT}Container '$container_name' is set up and running.${NC}"
}

# Function to start a container
start_container() {
    local container_name="$1"

    # Check if container exists
    if ! container_exists "$container_name"; then
        echo -e "${ERROR}Error:${NC} Container '$container_name' does not exist."
        exit 1
    fi

    if container_running "$container_name"; then
        echo -e "${WARNING}Notice:${NC} Container '$container_name' is already running."
    else
        docker start "$container_name"
        echo -e "${SUCCESS}Container '$container_name' started.${NC}"
    fi
}

# Function to stop a container
stop_container() {
    local container_name="$1"

    # Check if container exists
    if ! container_exists "$container_name"; then
        echo -e "${ERROR}Error:${NC} Container '$container_name' does not exist."
        exit 1
    fi

    if container_running "$container_name"; then
        docker stop "$container_name"
        echo -e "${SUCCESS}Container '$container_name' stopped.${NC}"
    else
        echo -e "${WARNING}Notice:${NC} Container '$container_name' is not running."
    fi
}

# Function to remove a container
remove_container() {
    local container_name="$1"

    # Check if container exists
    if ! container_exists "$container_name"; then
        echo -e "${ERROR}Error:${NC} Container '$container_name' does not exist."
        exit 1
    fi

    if container_running "$container_name"; then
        echo -e "${WARNING}Stopping running container '$container_name'...${NC}"
        docker stop "$container_name"
    fi

    echo -e "${WARNING}Removing container '$container_name'...${NC}"
    docker rm "$container_name"

    echo -e "${SUCCESS}Container '$container_name' has been removed.${NC}"
}

# Function to list all managed containers
list_containers() {
    echo -e "${WARNING}Listing all managed PostgreSQL containers:${NC}"
    local containers
#    name start with BASE_CONTAINER_NAME
    containers=$(docker ps -a --filter "name=${BASE_CONTAINER_NAME}*" --format "{{.Names}}|{{.Status}}|{{.Ports}}")

    if [[ -z "$containers" ]]; then
        echo -e "${ERROR}No containers found.${NC}"
        return
    fi

    withs="%-40s %-30s %-30s\n"

    printf "$withs" "NAME" "STATUS" "PORTS"
    printf "$withs" "----" "------" "-----"
    while IFS='|' read -r name status ports; do
        if [[ "$status" == *"Up"* ]]; then
            color=$SUCCESS
        else
#            color=$WARNING
            color=$NC
        fi
#        echo -e "${color}${name}${NC}" "${status}" "${ports}"
#        printf "$withs" "$NC$name" "$color$status" "$NC$ports"
#        printf "$withs" "$color$name" "$status" "$ports"
#        printf "${color}%-40s${NC} %-30s %-30s\n" "$name" "$status" "$ports"
        printf "${color}%-40s %-30s %-30s${NC}\n" "$name" "$status" "$ports"
    done <<< "$containers"
}

# Function to display the interactive menu
show_menu() {
    while true; do
        echo -e "\n"
        echo -e "=============================="
        echo -e "        DB Manager Menu        "
        echo -e "=============================="
        echo -e "${BLUE_DEEP}1. Create Container"
        echo -e "${SUCCESS}2. Start Container"
        echo -e "${INFO_RISKY}3. Stop Container"
        echo -e "${ERROR}4. Remove Container"
        echo -e "${BLUE_LIGHT}5. List Containers"
        echo -e "${PURPLE_LIGHT}6. Exit"
        echo -e "${NC}"

        read -p "Enter your choice [1-6]: " choice
        echo

        case "$choice" in
            1)
                # Create Container
                read -p "${ERROR}[required]${NC} Enter Feature Name (${GREY_LIGHT}e.g., ${WARNING}feature-login${NC}): " featureName
                if [[ -z "$featureName" ]]; then
                    echo -e "${ERROR}Feature name is required.${NC}"
                    continue
                fi

                read -p "Enter SQL Dump File Path (${GREY_LIGHT}default: ${WARNING}$DEFAULT_DUMP_PATH${NC}): " dumpFile
                dumpFile="${dumpFile:-$DEFAULT_DUMP_PATH}"
                if [[ ! -f "$dumpFile" ]]; then
                    echo -e "${ERROR}Error: File '$dumpFile' does not exist.${NC}"
                    continue
                fi

                read -p "Enter Database Suffix (${GREY_LIGHT}optional${NC}): " dbSuffix
                dbSuffix=$(sanitize_feature_name "$dbSuffix")
                dbSuffix="${dbSuffix//_/}"  # Remove any underscores

                read -p "Enter Host Port for PostgreSQL (${GREY_LIGHT}default: ${WARNING}$BASE_HOST_PORT${NC}): " hostPort
                hostPort="${hostPort:-$BASE_HOST_PORT}"
                if ! [[ "$hostPort" =~ ^[0-9]+$ ]] || (( hostPort < 1024 || hostPort > 65535 )); then
                    echo -e "${ERROR}Invalid port number. Please enter a number between 1024 and 65535.${NC}"
                    continue
                fi

                # Prompt for Database Name if not provided via CLI args
                if [[ -z "$DB_NAME" ]]; then
                    read -p "Enter Database Name (${GREY_LIGHT}default: ${WARNING}$BASE_DB_NAME${NC}): " dbName
                    dbName="${dbName:-$BASE_DB_NAME}"
                else
                    dbName="$DB_NAME"
                    echo -e "${GREEN}Using provided Database Name: $dbName${NC}"
                fi

                # Prompt for Database User if not provided via CLI args
                if [[ -z "$DB_USER" ]]; then
                    read -p "Enter Database User (${GREY_LIGHT}default: ${WARNING}$DEFAULT_DB_USER${NC}): " dbUser
                    dbUser="${dbUser:-$DEFAULT_DB_USER}"
                else
                    dbUser="$DB_USER"
                    echo -e "${GREEN}Using provided Database User: $dbUser${NC}"
                fi

                # Prompt for Database Password if not provided via CLI args
                if [[ -z "$DB_PASSWORD" ]]; then
                    read -s -p "Enter Database Password (${GREY_LIGHT}default: ${WARNING}$DEFAULT_DB_PASSWORD${NC}): " dbPassword
                    echo
                    dbPassword="${dbPassword:-$DEFAULT_DB_PASSWORD}"
                else
                    dbPassword="$DB_PASSWORD"
                    echo -e "${GREEN}Using provided Database Password.${NC}"
                fi

                create_container "$featureName" "$dumpFile" "$hostPort" "$dbSuffix" "$dbUser" "$dbPassword"
                ;;
            2)
                # Start Container
                start_container_menu
                ;;
            3)
                # Stop Container
                stop_container_menu
                ;;
            4)
                # Remove Container
                remove_container_menu
                ;;
            5)
                # List Containers
                list_containers
                ;;
            6)
                # Exit
                echo -e "${SUCCESS}Exiting DB-Manager. Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${ERROR}Invalid choice. Please select a number between 1 and 6.${NC}"
                ;;
        esac
    done
}

# Function to display and handle Start Container menu
start_container_menu() {
    # Get list of stopped containers
    local containers
    containers=$(docker ps -a --filter "name=${BASE_CONTAINER_NAME}*" --filter "status=exited" --format "{{.Names}}|{{.Status}}|{{.Ports}}")

    if [[ -z "$containers" ]]; then
        echo -e "${ERROR}No stopped containers available to start.${NC}"
        return
    fi

    echo -e "${WARNING}Select a container to start:${NC}"
    declare -a container_names
    index=1
    while IFS='|' read -r name status ports; do
        if [[ "$status" == *"Exited"* ]]; then
            echo -e "${NC}$index) $name - ${ERROR}Stopped${NC} - Ports: $ports"
            container_names+=("$name")
            ((index++))
        fi
    done <<< "$containers"

    echo -e "${PURPLE_LIGHT}0) Cancel${NC}"
    read -p "Enter your choice [0-$((index-1))]: " choice

    if [[ "$choice" -eq 0 || -z "$choice" ]]; then
        echo "Operation cancelled."
        return
    fi

    selected_container="${container_names[$((choice-1))]}"
    if [[ -z "$selected_container" ]]; then
        echo -e "${ERROR}Invalid selection.${NC}"
        return
    fi

    start_container "$selected_container"
}

# Function to display and handle Stop Container menu
stop_container_menu() {
    # Get list of running containers
    local containers
    containers=$(docker ps --filter "name=${BASE_CONTAINER_NAME}*" --filter "status=running" --format "{{.Names}}|{{.Status}}|{{.Ports}}")

    if [[ -z "$containers" ]]; then
        echo -e "${ERROR}No running containers available to stop.${NC}"
        return
    fi

    echo -e "${WARNING}Select a container to stop:${NC}"
    declare -a container_names
    index=1
    while IFS='|' read -r name status ports; do
        if [[ "$status" == *"Up"* ]]; then
            echo -e "${NC}$index) $name - ${SUCCESS}Running${NC} - Ports: $ports"
            container_names+=("$name")
            ((index++))
        fi
    done <<< "$containers"

    echo -e "${PURPLE_LIGHT}0) Cancel${NC}"
    read -p "Enter your choice [0-$((index-1))]: " choice

    if [[ "$choice" -eq 0 || -z "$choice" ]]; then
        echo "Operation cancelled."
        return
    fi

    selected_container="${container_names[$((choice-1))]}"
    if [[ -z "$selected_container" ]]; then
        echo -e "${ERROR}Invalid selection.${NC}"
        return
    fi

    stop_container "$selected_container"
}

# Function to display and handle Remove Container menu
remove_container_menu() {
    # Get list of all containers
    local containers
    containers=$(docker ps -a --filter "name=${BASE_CONTAINER_NAME}*" --format "{{.Names}}|{{.Status}}|{{.Ports}}")

    if [[ -z "$containers" ]]; then
        echo -e "${ERROR}No containers available to remove.${NC}"
        return
    fi

    echo -e "${WARNING}Select a container to remove:${NC}"
    declare -a container_names
    index=1
    while IFS='|' read -r name status ports; do
        if [[ "$status" == *"Up"* ]]; then
            display_status="${SUCCESS}Running${NC}"
        else
            display_status="${ERROR}Stopped${NC}"
        fi
        echo -e "${NC}$index) $name - $display_status - Ports: $ports"
        container_names+=("$name")
        ((index++))
    done <<< "$containers"

    echo -e "${PURPLE_LIGHT}0) Cancel${NC}"
    read -p "Enter your choice [0-$((index-1))]: " choice

    if [[ "$choice" -eq 0 || -z "$choice" ]]; then
        echo "Operation cancelled."
        return
    fi

    selected_container="${container_names[$((choice-1))]}"
    if [[ -z "$selected_container" ]]; then
        echo -e "${ERROR}Invalid selection.${NC}"
        return
    fi

    read -p "Are you sure you want to remove the container '$selected_container'? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        remove_container "$selected_container"
    else
        echo "Removal cancelled."
    fi
}

##########################
# Main Script Logic
##########################

# If no arguments are provided, show the menu
if [[ $# -lt 1 ]]; then
    show_menu
    exit 0
fi

COMMAND="$1"
shift  # Remove the first argument

case "$COMMAND" in
    create)
        # Initialize variables with default values
        FEATURE_NAME=""
        DUMP_FILE="$DEFAULT_DUMP_PATH"
        HOST_PORT=""
        DB_SUFFIX=""
        DB_USER="$DEFAULT_DB_USER"
        DB_PASSWORD="$DEFAULT_DB_PASSWORD"

        # Parse options
        while getopts ":n:f:p:d:u:w:h" opt; do
          case ${opt} in
            n )
              FEATURE_NAME="$OPTARG"
              ;;
            f )
              DUMP_FILE="$OPTARG"
              ;;
            p )
              HOST_PORT="$OPTARG"
              ;;
            d )
              DB_SUFFIX="$OPTARG"
              ;;
            u )
              DB_USER="$OPTARG"
              ;;
            w )
              DB_PASSWORD="$OPTARG"
              ;;
            h )
              usage
              ;;
            \? )
              echo -e "${ERROR}Invalid Option: -$OPTARG${NC}" >&2
              usage
              ;;
            : )
              echo -e "${ERROR}Option -$OPTARG requires an argument.${NC}" >&2
              usage
              ;;
          esac
        done

        # Validate required options
        if [[ -z "$FEATURE_NAME" ]]; then
            echo -e "${ERROR}Error:${NC} Feature name (-n) is required for create."
            usage
        fi

        # If DUMP_FILE is not provided via -f, use the default path
        if [[ -z "$DUMP_FILE" ]]; then
            DUMP_FILE="$DEFAULT_DUMP_PATH"
        fi

        if [[ ! -f "$DUMP_FILE" ]]; then
            echo -e "${ERROR}Error:${NC} File '$DUMP_FILE' does not exist."
            exit 1
        fi

        # If DB_SUFFIX not provided, leave it empty
        if [[ -n "$DB_SUFFIX" ]]; then
            DB_SUFFIX=$(sanitize_feature_name "$DB_SUFFIX")
            # Ensure no trailing underscores
            DB_SUFFIX=$(echo "$DB_SUFFIX" | sed 's/_*$//')
        else
            DB_SUFFIX=""
        fi

        # Prevent duplication if db_suffix is same as BASE_DB_NAME
        if [[ "$DB_SUFFIX" == "${BASE_DB_NAME}" ]]; then
            DB_SUFFIX=""
        fi

        create_container "$FEATURE_NAME" "$DUMP_FILE" "$HOST_PORT" "$DB_SUFFIX" "$DB_USER" "$DB_PASSWORD"
        ;;
    start)
        FEATURE_NAME=""
        # Parse options
        while getopts ":n:h" opt; do
          case ${opt} in
            n )
              FEATURE_NAME="$OPTARG"
              ;;
            h )
              usage
              ;;
            \? )
              echo -e "${ERROR}Invalid Option: -$OPTARG${NC}" >&2
              usage
              ;;
            : )
              echo -e "${ERROR}Option -$OPTARG requires an argument.${NC}" >&2
              usage
              ;;
          esac
        done

        if [[ -z "$FEATURE_NAME" ]]; then
            echo -e "${ERROR}Error:${NC} Feature name (-n) is required to start a container."
            usage
        fi

        # Determine container name
        sanitized_feature_name=$(sanitize_feature_name "$FEATURE_NAME")
        container_name="${BASE_CONTAINER_NAME}_${sanitized_feature_name}"

        start_container "$container_name"
        ;;
    stop)
        FEATURE_NAME=""
        # Parse options
        while getopts ":n:h" opt; do
          case ${opt} in
            n )
              FEATURE_NAME="$OPTARG"
              ;;
            h )
              usage
              ;;
            \? )
              echo -e "${ERROR}Invalid Option: -$OPTARG${NC}" >&2
              usage
              ;;
            : )
              echo -e "${ERROR}Option -$OPTARG requires an argument.${NC}" >&2
              usage
              ;;
          esac
        done

        if [[ -z "$FEATURE_NAME" ]]; then
            echo -e "${ERROR}Error:${NC} Feature name (-n) is required to stop a container."
            usage
        fi

        # Determine container name
        sanitized_feature_name=$(sanitize_feature_name "$FEATURE_NAME")
        container_name="${BASE_CONTAINER_NAME}_${sanitized_feature_name}"

        stop_container "$container_name"
        ;;
    remove)
        FEATURE_NAME=""
        # Parse options
        while getopts ":n:h" opt; do
          case ${opt} in
            n )
              FEATURE_NAME="$OPTARG"
              ;;
            h )
              usage
              ;;
            \? )
              echo -e "${ERROR}Invalid Option: -$OPTARG${NC}" >&2
              usage
              ;;
            : )
              echo -e "${ERROR}Option -$OPTARG requires an argument.${NC}" >&2
              usage
              ;;
          esac
        done

        if [[ -z "$FEATURE_NAME" ]]; then
            echo -e "${ERROR}Error:${NC} Feature name (-n) is required to remove a container."
            usage
        fi

        # Determine container name
        sanitized_feature_name=$(sanitize_feature_name "$FEATURE_NAME")
        container_name="${BASE_CONTAINER_NAME}_${sanitized_feature_name}"

        remove_container "$container_name"
        ;;
    list)
        list_containers
        ;;
    menu)
        show_menu
        ;;
    *)
        echo -e "${ERROR}Error:${NC} Unknown command '$COMMAND'."
        usage
        ;;
esac
