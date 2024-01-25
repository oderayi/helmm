#!/usr/bin/env bash

# Description: This script is used to generate release note for a release.
# Dependencies: This script depends on the changelog files (.tmp/changelogs/**) and environment variables generated by the generate-changelog.sh script.
# Requirements: bash >= v4.0.0, jq, curl, git, helm, mo
# Usage: .github/workflows/scripts/generate-release-note.sh release_version last_release_tag ttk-test-cases-version example-backend-version
# Environment variables: AUTO_RELEASE_TOKEN

set -e

####################################
# Environment and arguments check  #
####################################

# Check if the current shell is bash and the version is >= 4.0.0
if [ -z "$BASH_VERSION" ] || [ "${BASH_VERSION:0:1}" -lt 4 ]; then
    echo "This script requires bash >= v4.0.0. Please install bash >= v4.0.0 and try again."
    exit 1
fi

# Check if the AUTO_RELEASE_TOKEN environment variable is set
if [ -z "$AUTO_RELEASE_TOKEN" ]; then
    echo "The AUTO_RELEASE_TOKEN environment variable is not set. Please set the AUTO_RELEASE_TOKEN environment variable and try again."
    usage
    exit 1
fi

# Check if the release_version argument is provided
if [ -z "$1" ]; then
    echo "The \"release_version\" argument is not provided. Please provide the \"release_version\" argument and try again."
    usage
    exit 1
fi

# Check if the last_release_tag argument is provided
if [ -z "$2" ]; then
    echo "The \"last_release_tag\" argument is not provided. Please provide the \"last_release_tag\" argument and try again."
    usage
    echo "last_release_tag = [ null | tag of the last release ]"
    exit 1
fi

# Check if the ttk-test-cases-version argument is provided
if [ -z "$3" ]; then
    echo "The \"ttk-test-cases-version\" argument is not provided. Please provide the \"ttk-test-cases-version\" argument and try again."
    usage
    exit 1
fi

# Check if example-backend-version argument is provided
if [ -z "$3" ]; then
    echo "The \"example-backend-version\" argument is not provided. Please provide \"example-backend-version\" argument and try again."
    usage
    exit 1
fi

# We read the changelogs, commits, tags etc. from the temporary directory
dir=".tmp"

# Ensure .tmp/changelogs directory exists and there are files in there
if [ ! -d "$dir/changelogs" ] || [ ! "$(ls -A $dir/changelogs)" ]; then
    echo "The .tmp/changelogs directory does not exist or is empty. Please run the generate-changelog.sh script and try again."
    exit 1
fi

######################
# Global variables   #
######################
declare -A last_release_tags
declare -A current_tags

release_version=$1
# 'last_release_tag' is the last release tag, if not provided, it will be the last tag in the current branch
if [ -z "$2" ] || [ $2 == null ]; then
    last_release_tag=$(git describe --tags --abbrev=0)
else
    last_release_tag=$2
fi
test_cases_version=$3
example_backend_version=$4

######################
# Helper functions   #
######################

# Usage instructions
usage() {
    echo "export AUTO_RELEASE_TOKEN=<github token>"
    echo "generate-release-note.sh release_version last_release_tag ttk-test-cases-version example-backend-version"
}

# Generate "Breaking Changes" section of the release note
breaking_changes() {
    # Loop over each json file in .tmp/changelogs directory
    # Extract the pull request titles from the json file into an associative array indexed by the file basename
    # The value of the associative array is an array of breaking changes
    # We then iterate through the associative array and generate the breaking changes section
    declare -A breaking_changes
    for file in $dir/changelogs/*.json
    do
        repository=$(basename $file | cut -d'.' -f1)
        breaking_files=$(cat $file | jq -r '.files[] | select(.filename | contains("default.json", "migration")) | "  * \(.filename): (\(.blob_url))"')
        breaking_commits=$(cat $file | jq -r '.commits[] | select(.commit.message | contains("BREAKING CHANGE")) | .commit.message = (.commit.message | split("\n")[0]) |  "  * \(.commit.message): (\(.commit.url))"')
        breaking_changes[$repository]=$(echo -e "$breaking_files\n$breaking_commits")
    done

    # Generate breaking changes section
    # We loop over each repository in the associative array and generate the breaking changes section
    # If there are no breaking changes, we return an empty string
    # If there are breaking changes, we return the breaking changes section
    breaking_changes_section=""
    for repository in "${!breaking_changes[@]}"
    do
        if [[ ${breaking_changes[$repository]} ]]
        then
            breaking_changes_section+=$(echo -e "\n### $repository\n${breaking_changes[$repository]}")
        fi
    done

    echo "$breaking_changes_section"
}

# Generate release summary points section of the release note
release_summary_points() {
    echo "_Release summary points go here..._"
}

# Generate "New Features" section of the release note
new_features() {
    new_features=""
    for file in $dir/changelogs/*.json
    do
        repository=$(basename $file | cut -d'.' -f1)
        pr_title=$(cat $file |  jq -r '.commits[].commit | select(.message | startswith("feat")) .message | split("\n")[0] as $pr_title | "* \($pr_title)"')
        echo "$pr_title" | while IFS= read -r line
        do
            description=$(echo "$line" | awk -F ': ' '{print $2}' | awk -F ' \\(#' '{print $1}')
            issue_number=$(echo "$line" | awk -F '[/#)]' '{print $3}')
            pr_number=$(echo "$line" | sed -n -e 's/.*(#\([^)]*\))$/\1/p')
            echo -e "* **mojaloop/#$issue_number** $description ([mojaloop/#$pr_number](https://github.com/mojaloop/$repository/pull/$pr_number)), closes [mojaloop/#$issue_number](https://github.com/mojaloop/project/issues/$issue_number)"
            
        done
    done
}

# Generate "Bug Fixes" section of the release note
bug_fixes() {
    bug_fixes=""
    for file in $dir/changelogs/*.json
    do
        repository=$(basename $file | cut -d'.' -f1)
        bug_fixes+=$(cat $file |  jq -r '.commits[].commit | select(.message | startswith("fix(")) .message | split("\n")[0] as $pr_title | "* \($pr_title)"' | sort -u)
    done

    echo "$bug_fixes"
}

# Generate "Application Versions" section of the release note
application_versions() {
    application_versions=""
    line_number=0

    # List services that have changed first
    for repository in "${!current_tags[@]}"
    do
        if [[ $repository == mojaloop* ]]
        then
            if [[ ${current_tags[$repository]} != ${last_release_tags[$repository]} ]]
            then
                line_number=$(( line_number+1 ))
                repository_short_name=$(echo $repository | cut -d'/' -f2)
                application_versions+=$(echo -e "\n$line_number. $repository_short_name: ${last_release_tags[$repository]} -> \
                    [${current_tags[$repository]}](https://github.com/$repository/releases/${current_tags[$repository]}) \
                    ([Compare](https://github.com/$repository/compare/${last_release_tags[$repository]}...${current_tags[$repository]}))")
            fi
        fi
    done

    # Add services that have not changed below
    for repository in "${!current_tags[@]}"
    do
        if [[ $repository == mojaloop* ]]
        then
            if [[ ${current_tags[$repository]} == ${last_release_tags[$repository]} ]]
            then
                line_number=$((line_number+1))
                repository_short_name=$(echo $repository | cut -d'/' -f2)
                application_versions+=$(echo -e "\n$line_number. $repository_short_name: [${current_tags[$repository]}](https://github.com/$repository/releases/${current_tags[$repository]})")
            fi
        fi
    done

    echo "$application_versions"
}

# Generate "Individual Contributors" section of the release note
individual_contributors() {
    # Loop over each json file in .tmp/changelogs directory and extract the commit author login
    # We then remove duplicates, sort the list, and convert the list to a comma separated string
    individual_contributors=""
    for file in $dir/changelogs/*.json
    do
        repository=$(basename $file | cut -d'.' -f1)
        individual_contributors+=$(cat $file | jq -r '.commits[].author | select(.login != null) .login'  | sed 's/^/@/' | tr '\n' ',' | sed 's/,$//g' | sed 's/,/, /g')
    done

    echo "$individual_contributors"
}

# Return the version of the TTK test cases used in the release
ttk_test_cases_version() {
    echo "$test_cases_version"
}

# Return the version of the example mojaloop backend used in testing the release
example_mojaloop_backend_version() {
    echo "$example_backend_version"
}

#####################################################################
# Read the release tags (past and current) into memory.             #
# These are used by helper functions to generate different sections #
# of the release note.                                              # 
#####################################################################

# Read last release tags into associative array 'last_release_tags' 
while IFS= read -r line
do
    if [[ $line == *"repository:"* ]]
    then
        repository=$(echo $line | cut -d':' -f2 | cut -d' ' -f1)
        last_release_tags[$repository]=null
    fi
    
    if [[ $line == *"tag:"* ]]
    then
        tag=$(echo $line | cut -d':' -f2)
        last_release_tags[$repository]=$tag
    fi
done < "$dir/tags/last-release-tags.log"

# Read current tags into associative array 'current_tags'
while IFS= read -r line
do
    if [[ $line == *"repository:"* ]]
    then
        repository=$(echo $line | cut -d':' -f2 | cut -d' ' -f1)
        current_tags[$repository]=null
    fi
    
    if [[ $line == *"tag:"* ]]
    then
        tag=$(echo $line | cut -d':' -f2)
        current_tags[$repository]=$tag
    fi
done < "$dir/tags/current-tags.log"

#########################
# Generate release note #
#########################

# We use a template (.github/workflows/templates/release-note-template.md) to generate the release note
# The template contains placeholders that are replaced with the PR titles from the changelogs and other information

# Populate and export template variables for "mo"
export RELEASE_DATE=$(date +%Y-%m-%d)
export BREAKING_CHANGES=$(breaking_changes)
[[ -z $BREAKING_CHANGES  ]] && export BREAKING_CHANGES_STATUS_TEXT="non-breaking" || export BREAKING_CHANGES_STATUS_TEXT="breaking"
[[ -z $BREAKING_CHANGES  ]] && BREAKING_CHANGES="There are no breaking changes in this release."
export RELEASE_SUMMARY_POINTS=$(release_summary_points)
export NEW_FEATURES=$(new_features)
[[ -z $NEW_FEATURES  ]] && NEW_FEATURES="There are no new features in this release."
export BUG_FIXES=$(bug_fixes)
[[ -z $BUG_FIXES  ]] && BUG_FIXES="There are no bug fixes in this release."
export APPLICATION_VERSIONS=$(application_versions)
export TTK_TEST_CASES_VERSION=$(ttk_test_cases_version)
export EXAMPLE_MOJALOOP_BACKEND_VERSION=$(example_mojaloop_backend_version)
export CURRENT_RELEASE_VERSION=$release_version
export LAST_RELEASE_VERSION=$(echo $last_release_tag | cut -d'/' -f2)
export INDIVIDUAL_CONTRIBUTORS=$(individual_contributors)

# We use mustache bash template engine to replace the placeholders in the template with the template variables
# Mustache bash template engine is a bash implementation of mustache template engine
# It works better with newline characters than sed
release_note=$(cat .github/workflows/templates/release-note-template.md | mo) 

if [[ $release_note == *"{{"* ]] || [[ -z $release_note ]]
then
    echo "Error: One or more template variables are not replaced. Please check the template variables and try again."
    exit 1
fi

# Write release_note content to .changelog/release-$CURRENT_RELEASE_VERSION.md
mkdir -p .changelog
echo "$release_note" > .changelog/release-$CURRENT_RELEASE_VERSION.md

######################
# Cleanup            #
######################

# Remove temporary directory and files
rm -rf $dir

echo "Release note generated at .changelog/release-$CURRENT_RELEASE_VERSION.md"
