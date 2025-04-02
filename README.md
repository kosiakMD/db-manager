# Database (in Docker) Management

This project includes a Docker-based DB-Manager script to simplify the management of multiple PostgreSQL instances for various features or environments.

You need to have the database dump and use the manager to handle your PostgreSQL Docker containers.

## Prerequisites

Ensure you have the following installed:

- **Docker**: [Install Docker](https://docs.docker.com/get-docker/)

## Setup and Usage

### Run the Docker **DB-Manager**

Launch the interactive DB-Manager to manage your Docker containers.

```bash
'./path-to-file/db-manager.sh menu'
```

Or add a command to your e.g., `package.json` 

```json
{
  "scripts": {
    "infra:db-manager": "./path-to-bash-file.sh menu"
  }
}
```

To run straightforwardly:
```bash
  npm run infra:db:manage
```

### Example Workflow

### 1. Run the **DB-Manager** to Manage Containers

Run npm script:

  ```bash
  npm run infra:db:manage
  ```

Use the interactive menu after run DB-Manager to start, stop, remove, or list your PostgreSQL Docker containers as needed.

Menu Options:

`1. Create Container` - Create a new PostgreSQL container.</br>
`2. Start Container` - Start an existing PostgreSQL container.</br>
`3. Stop Container` - Stop a running PostgreSQL container.</br>
`4. Remove Container` - Remove an existing PostgreSQL container.</br>
`5. List Container` - List all managed PostgreSQL containers.</br>
`6. Exit` - Exit the DB-Manager.</br>

### 2. Run the **DB-Manager** to Create a New Container

#### - Without Environment Variables

  ```bash
  npm run infra:db:manage
  ```

- Select `1. Create Container` from the menu.
- Provide Inputs When Prompted:
  - <span style="color: red">[required]</span> Feature Name: `feature-orders`
  - SQL Dump File Path: Press Enter to use `./db.sql` <i style="color: grey">(default)</i>.
  - Database Suffix: e.g., `orders` <u style="color: grey">(optional)</u>
  - Host Port for PostgreSQL: `5432` <i style="color: grey">(default)</i>
  - Database Name: Press Enter to use `db-local` <i style="color: grey">(default)</i> or enter a custom name.
  - Database User: Press Enter to use `user` <i style="color: grey">(default)</i> or enter a custom user.
  - Database Password: Press Enter to use `password` <i style="color: grey">(default)</i> or enter a custom password.

#### - Using Environment Variables

  ```bash
  DB_NAME="db-custom" DB_USER="admin" DB_PASSWORD="securepass" npm run infra:db-manager
  ```

  Behavior: When selecting Create Container from the interactive menu, the script will automatically use `db-custom` as the Database Name, admin as the Database User, and `securepass` as the Database Password without prompting.

# Examples:

## Main menu
<img width="254" alt="Screenshot 2024-10-31 at 17 56 28" src="https://github.com/user-attachments/assets/19126530-b721-4597-9335-d2f898fe7a41">

## Run menu
<img width="732" alt="Screenshot 2024-10-31 at 17 58 55" src="https://github.com/user-attachments/assets/b1928a01-3ef7-4e03-b94c-52d4d4fafee8">
<img width="675" alt="Screenshot 2024-10-31 at 17 57 42" src="https://github.com/user-attachments/assets/85cf4c0b-0889-4b3d-afa1-0870b9e5ee92">

## List
<img width="779" alt="Screenshot 2024-10-31 at 17 59 57" src="https://github.com/user-attachments/assets/7f5aee0e-1b76-47de-a1ba-1c050acea3ff">

## Start menu
<img width="356" alt="Screenshot 2024-10-31 at 17 59 45" src="https://github.com/user-attachments/assets/7a60cf2b-9fd3-4508-bf0e-04a36c972cb7">

## Stop menu
<img width="537" alt="Screenshot 2024-10-31 at 17 59 19" src="https://github.com/user-attachments/assets/5e9fddc3-2fa6-4a1c-a148-fe1e0f3921e9">







