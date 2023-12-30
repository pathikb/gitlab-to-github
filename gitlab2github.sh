#!/bin/bash

# Set variables
GITLAB_DOMAIN="<domain-name>" # Replace with your GitLab domain
GITLAB_API="https://$GITLAB_DOMAIN/api/v4"
GITLAB_TOKEN="" # Replace with your GitLab personal access token
GITHUB_API="https://api.github.com"
GITHUB_TOKEN="" # Replace with your GitHub personal access token
GITHUB_USERNAME="" # Replace with your GitHub username
GITHUB_ORG="" # Set this if you want to create the repositories under a GitHub organization

# Function to check if GitHub repository exists
check_github_repo() {
  local repo_name=$1
  local github_repo_url="$GITHUB_API/repos/${GITHUB_ORG:-$GITHUB_USERNAME}/$repo_name"
  curl -o /dev/null -s -f -I -H "Authorization: token $GITHUB_TOKEN" "$github_repo_url"
  return $?
}

# Function to get GitLab projects from a specific page
get_gitlab_projects() {
  local page=$1
  # curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects?per_page=5&page=$page"
  local response=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects?per_page=50&page=$page&order_by=created_at&sort=desc")
  # Remove control characters before passing it to jq
  echo "$response" | tr -d '\000-\031'
}

# Initialize page number
page=1

# Fetch the first page of projects
gitlab_projects=$(get_gitlab_projects $page)

# Loop through each page and migrate projects
  while [ "$(echo "$gitlab_projects" | jq '. | length')" -gt 0 ]; do
  echo "Migrating projects from page $page..."

  # Loop through each project and migrate
  echo "$gitlab_projects" | jq -c '.[]' | while read -r project; do
    full_name=$(echo "$project" | jq -r '.path_with_namespace')
    name=$(echo "$project" | jq -r '.name' | tr ' ' '-') # Replace spaces with hyphens
    description=$(echo "$project" | jq -r '.description')

    # Check if GitHub repository already exists
    echo "Checking if $name exists on GitHub..."
    if check_github_repo "$name"; then
      echo "Repository $name already exists on GitHub, skipping migration."
      continue
    fi

    # Create GitHub repository
    echo "Creating GitHub repository for $name..."
    github_payload=$(jq -n --arg name "$name" --arg description "$description" '{
      name: $name,
      description: $description,
      private: true
    }')

    if [[ -n $GITHUB_ORG ]]; then
      github_repo=$(curl -X POST -H "Authorization: token $GITHUB_TOKEN" -d "$github_payload" "$GITHUB_API/orgs/$GITHUB_ORG/repos")
    else
      github_repo=$(curl -X POST -H "Authorization: token $GITHUB_TOKEN" -d "$github_payload" "$GITHUB_API/user/repos")
    fi

    # Clone the GitLab repository using the access token and rename the directory
    echo "Cloning $full_name from GitLab..."
    git clone --mirror "https://oauth2:$GITLAB_TOKEN@$GITLAB_DOMAIN/${full_name}.git" "$name"

    # Push to GitHub repository
    echo "Pushing $name to GitHub..."
    cd "$name"
    git push --mirror "https://$GITHUB_TOKEN@github.com/${GITHUB_ORG:-$GITHUB_USERNAME}/${name}.git"
    cd ..
    rm -rf "$name" # Remove the repository after push

    echo "Migration of $name completed."

  done

  # Get the next page of projects
  ((page++))
  gitlab_projects=$(get_gitlab_projects $page)
done

echo "All projects have been migrated."